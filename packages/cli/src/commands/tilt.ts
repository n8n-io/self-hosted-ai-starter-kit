import type { AiRuntime, Config, N8nVariant } from '../schemas/config'
import type { ModelsCatalogue, VllmModel } from '../schemas/models'
import type { TiltProject, TiltResource, TiltResources } from '../schemas/tilt'
import { createHash } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { dirname, join, posix, relative, sep } from 'node:path'
import { z } from 'zod'
import { configSchema, N8N_VARIANTS } from '../schemas/config'
import { tiltResourcesSchema } from '../schemas/tilt'
import { parseEnvContent } from '../utils/env'
import { findFiles } from '../utils/files'
import { runCommand } from '../utils/format'
import { logger } from '../utils/logger'
import { modelEntries, OLLAMA_ENDPOINT, parseModelList, readModelsCatalogue, vllmContainerName, vllmEndpoint } from '../utils/models'
import { MANIFEST_FILENAME } from './secrets'

const ENV_FILENAME = '.env'

export const TILT_SUBCOMMANDS = ['resources'] as const

/**
 * One self-contained compose file per N8N_VARIANT, in cascade order: each file extends the one before it
 * (see ../../../../compose/n8n/docker-compose.yml and ../../../../SPEC.md). Tilt runs the last file and
 * watches the others, with the .env beside them, so edits reload it too.
 */
export const N8N_VARIANT_CASCADE: Record<N8nVariant, string[]> = {
  dev: ['./compose/n8n/docker-compose.yml'],
  build: ['./compose/n8n/docker-compose.yml', './compose/n8n/docker-compose.build.yml'],
  community: ['./compose/n8n/docker-compose.yml', './compose/n8n/docker-compose.build.yml', './compose/n8n/docker-compose.community.yml'],
  enterprise: ['./compose/n8n/docker-compose.yml', './compose/n8n/docker-compose.build.yml', './compose/n8n/docker-compose.community.yml', './compose/n8n/docker-compose.enterprise.yml'],
}

/** The compose file of a service directory, relative to the Tiltfile */
function composeFile(group: string, service: string): string {
  return `./compose/${group}/${service}/docker-compose.yml`
}

/** The .env beside a compose file: its project reads it by itself, Tilt only watches it when told to (see ../../../../SPEC.md) */
function envFile(file: string): string {
  return `${posix.dirname(file)}/${ENV_FILENAME}`
}

type ResourceOptions = Partial<Omit<TiltResource, 'service' | 'labels'>>

function resource(service: string, labels: TiltResource['labels'], options: ResourceOptions = {}): TiltResource {
  return {
    service,
    name: options.name ?? service,
    labels,
    resource_deps: options.resource_deps ?? [],
    links: options.links ?? [],
    infer_links: options.infer_links ?? true,
    auto_init: options.auto_init ?? true,
    enabled: options.enabled ?? true,
  }
}

/** One docker_compose() call; the .env beside the entry file is watched on top of the given watch list */
function project(files: string[], resources: TiltResource[], options: Partial<Omit<TiltProject, 'files' | 'resources'>> = {}): TiltProject {
  const { watch = [], ...rest } = options
  return { files, watch: [...watch, envFile(files[0]!)], profiles: [], ...rest, resources }
}

/** The model server projects: one ollama server pulling every model, or one vllm container per model (see ../../../../SPEC.md) */
function modelProjects(config: Config, catalogue: ModelsCatalogue, models: string[]): TiltProject[] {
  const runtime: AiRuntime = config.AI_RUNTIME
  const service = `${config.AI_ENGINE}-${runtime}`
  const file = composeFile('models', config.AI_ENGINE)
  const entries = modelEntries(catalogue, config.AI_ENGINE, runtime)

  if (config.AI_ENGINE === 'ollama') {
    const tags = models.map(id => entries.find(entry => entry.id === id)!.model)
    return [project([file], [
      // with no model listed the server waits to be started by hand
      resource(service, ['models'], { name: 'ollama', infer_links: false, auto_init: models.length > 0 }),
    ], {
      project_name: 'ollama',
      profiles: [runtime],
      override: { services: { [service]: { environment: { MODELS: tags.join(',') } } } },
    })]
  }

  return models.map((id) => {
    const entry = entries.find(entry => entry.id === id) as VllmModel
    const name = vllmContainerName(id)
    return project([file], [
      resource(service, ['models'], { name, infer_links: false }),
    ], {
      project_name: name,
      profiles: [runtime],
      override: { services: { [service]: { container_name: name, environment: { MODEL: entry.model, MODEL_ARGS: entry.args } } } },
    })
  })
}

/** The label of a gateway service that carries the hash of its generated config, see ../../../../SPEC.md */
export const GATEWAY_CONFIG_HASH_LABEL = 'n8n-starter.config-hash'

/**
 * The gateway projects, enabled by AI_GATEWAY: litellm with its database, its model list replaced by one entry per
 * model of AI_MODELS, named after the catalogue id and pointing at the engine (see ../../../../SPEC.md). The list is
 * JSON, which the proxy reads as YAML, and its hash labels the service so a changed list recreates the container.
 * The gateway does not wait for the model servers, it only proxies to them.
 */
function gatewayProjects(config: Config, catalogue: ModelsCatalogue, models: string[]): TiltProject[] {
  const entries = modelEntries(catalogue, config.AI_ENGINE, config.AI_RUNTIME)
  const modelList = models.map((id) => {
    const { model } = entries.find(entry => entry.id === id)!
    return {
      model_name: id,
      litellm_params: config.AI_ENGINE === 'ollama'
        ? { model: `ollama_chat/${model}`, api_base: OLLAMA_ENDPOINT }
        : { model: `hosted_vllm/${model}`, api_base: vllmEndpoint(id), api_key: 'os.environ/VLLM_API_KEY' },
    }
  })
  const enabled = config.AI_GATEWAY === 'litellm'
  const content = JSON.stringify({ model_list: modelList }, null, 2)
  const hash = createHash('sha256').update(content).digest('hex').slice(0, 16)

  return [project([composeFile('models', 'litellm')], [
    resource('litellm-db', ['models'], { infer_links: false, enabled }),
    // the root of the host is the OpenAPI page, the link goes straight to the dashboard
    resource('litellm', ['models'], { resource_deps: ['litellm-db'], links: [`litellm.${config.DOMAIN}/ui`], enabled }),
  ], {
    override: {
      configs: { 'litellm-config': { content } },
      // compose and Tilt compare the service, not the content of its config: the label recreates the proxy with a new list
      services: { litellm: { labels: [`${GATEWAY_CONFIG_HASH_LABEL}=${hash}`] } },
    },
  })]
}

/**
 * The compose projects the Tiltfile registers for a root .env, and which of their resources are enabled
 * and auto-started: every project of the catalogue is listed so disabled services stay visible in the Tilt
 * UI; dev is one n8n container on sqlite without a storage service, build adds postgres (with pgadmin) and the
 * external task runner, community and enterprise run in queue mode (redis, a worker and its task runner, a
 * webhook processor at hooks.<DOMAIN>), enterprise adds S3 binary data (garage), AI_GATEWAY a gateway. A project whose
 * directory is one of `secretDirs` carries it as `secrets`, the filter of its secrets button. Throws on an AI_MODELS id
 * the engine does not serve on the runtime. See ../../../../SPEC.md.
 */
export function tiltResources(config: Config, catalogue: ModelsCatalogue, secretDirs: string[] = []): TiltResources {
  const domain = config.DOMAIN
  // the variants form a cascade, so a tier enables what every later variant needs too
  const atLeast = (variant: N8nVariant) => N8N_VARIANTS.indexOf(config.N8N_VARIANT) >= N8N_VARIANTS.indexOf(variant)
  const build = atLeast('build')
  const queue = atLeast('community')
  const enterprise = atLeast('enterprise')
  const models = parseModelList(config.AI_MODELS)

  const served = modelEntries(catalogue, config.AI_ENGINE, config.AI_RUNTIME).map(entry => entry.id)
  const unknown = models.filter(id => !served.includes(id))
  if (unknown.length > 0)
    throw new Error(`AI_MODELS ${unknown.join(', ')}: not served by ${config.AI_ENGINE} on ${config.AI_RUNTIME}, available: ${served.join(', ') || '(none)'} (see compose/models/models.json)`)

  const cascade = N8N_VARIANT_CASCADE[config.N8N_VARIANT]

  const projects: TiltProject[] = [
    // ./compose/proxy
    project([composeFile('proxy', 'docker-socket-proxy')], [resource('docker-socket-proxy', ['proxy'])]),
    project([composeFile('proxy', 'traefik')], [resource('traefik', ['proxy'], { links: [`traefik.${domain}`], infer_links: false })]),
    // ./compose/storage
    project([composeFile('storage', 'postgres')], [resource('postgres', ['storage'], { infer_links: false, enabled: build })]),
    project([composeFile('storage', 'pgadmin')], [resource('pgadmin', ['storage'], { resource_deps: ['postgres'], links: [`pgadmin.${domain}`], auto_init: false, enabled: build })]),
    project([composeFile('storage', 'redis')], [resource('redis', ['storage'], { infer_links: false, enabled: queue })]),
    project([composeFile('storage', 'redis-insight')], [resource('redisinsight', ['storage'], { resource_deps: ['redis'], links: [`redisinsight.${domain}`], auto_init: false, enabled: queue })]),
    project([composeFile('storage', 'garage')], [
      resource('garage', ['storage'], { links: [`s3.${domain}`, `web.${domain}`], auto_init: false, enabled: enterprise }),
      resource('garage-webui', ['storage'], { links: [`s3ui.${domain}`], auto_init: false, enabled: enterprise }),
    ]),
    // ./compose/services
    project([composeFile('services', 'qdrant')], [resource('qdrant', ['services'], { auto_init: false })]),
    // ./compose/n8n: the variant's file, its parents watched; the external task runner from build, a worker pair and a webhook processor in queue mode
    project([cascade[cascade.length - 1]!], [
      resource('n8n', ['n8n'], { resource_deps: [...(build ? ['postgres'] : []), ...(queue ? ['redis'] : [])], links: [domain] }),
      ...(build ? [resource('n8n-runner', ['n8n'], { resource_deps: ['n8n'] })] : []),
      ...(queue
        ? [
            resource('n8n-worker', ['n8n'], { resource_deps: ['n8n', 'redis'], infer_links: false }),
            resource('n8n-worker-runner', ['n8n'], { resource_deps: ['n8n-worker'], infer_links: false }),
            resource('n8n-webhook', ['n8n'], { resource_deps: ['n8n', 'redis'], links: [`hooks.${domain}`], infer_links: false }),
          ]
        : []),
    ], { watch: cascade.slice(0, -1) }),
    // ./compose/models: the gateway, then the engine
    ...gatewayProjects(config, catalogue, models),
    ...modelProjects(config, catalogue, models),
  ]

  // the directory is an exact `secrets read` filter: it lists the .env of this project and no other
  const withSecrets = projects.map((entry) => {
    const dir = posix.normalize(posix.dirname(entry.files[0]!))
    return secretDirs.includes(dir) ? { ...entry, secrets: dir } : entry
  })

  return tiltResourcesSchema.parse({ config: { ...config, AI_MODELS: models }, projects: withSecrets })
}

/** The directories that hold a .env.secrets.json, relative to rootDir with forward slashes, as the plan names its compose files */
export async function secretDirectories(rootDir: string): Promise<string[]> {
  return (await findFiles(rootDir, MANIFEST_FILENAME)).map(file => relative(rootDir, dirname(file)).split(sep).join('/'))
}

/** The validated root .env; throws naming the file when it is missing or a key is invalid */
export async function readRootConfig(rootDir: string): Promise<Config> {
  const file = join(rootDir, ENV_FILENAME)
  let content: string
  try {
    content = await readFile(file, 'utf-8')
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT')
      throw error
    throw new Error(`No ${ENV_FILENAME} file found in ${rootDir}. Run ${runCommand('setup')} first.`)
  }
  const result = configSchema.safeParse(parseEnvContent(content))
  if (!result.success)
    throw new Error(`Invalid ${file}:\n${z.prettifyError(result.error)}`)
  return result.data
}

/**
 * `tilt resources`: the resource plan of the root .env as JSON on stdout, nothing else; the Tiltfile
 * decodes it and registers every project (see ../../../../Tiltfile). Exit code 1 with the reason when
 * the .env, the catalogue or an AI_MODELS id is invalid.
 */
export async function tilt(rootDir = process.cwd(), [subcommand]: string[] = []) {
  if (subcommand !== 'resources') {
    logger.error(`${subcommand === undefined ? 'Missing' : `Unknown`} sub-command${subcommand === undefined ? '' : ` "${subcommand}"`} for tilt. Expected one of: ${TILT_SUBCOMMANDS.join(', ')}`)
    process.exitCode = 1
    return
  }
  try {
    const config = await readRootConfig(rootDir)
    const catalogue = await readModelsCatalogue(rootDir)
    console.log(JSON.stringify(tiltResources(config, catalogue, await secretDirectories(rootDir)), null, 2))
  } catch (error) {
    logger.error((error as Error).message)
    process.exitCode = 1
  }
}
