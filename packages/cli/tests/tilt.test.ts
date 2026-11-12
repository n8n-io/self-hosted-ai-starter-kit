import type { Config } from '../src/schemas/config'
import type { ModelsCatalogue } from '../src/schemas/models'
import type { TiltResources } from '../src/schemas/tilt'
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import { GATEWAY_CONFIG_HASH_LABEL, N8N_VARIANT_CASCADE, readRootConfig, secretDirectories, tilt, tiltResources } from '../src/commands/tilt'
import { AI_ENGINES, AI_GATEWAYS, N8N_VARIANTS } from '../src/schemas/config'
import { tiltResourcesSchema } from '../src/schemas/tilt'
import { parseEnvContent } from '../src/utils/env'
import { setLogLevel } from '../src/utils/logger'
import { readModelsCatalogue } from '../src/utils/models'

const { logErrorMock } = vi.hoisted(() => ({ logErrorMock: vi.fn() }))

vi.mock('@clack/prompts', () => ({
  intro: vi.fn(),
  outro: vi.fn(),
  cancel: vi.fn(),
  log: { info: vi.fn(), warn: vi.fn(), success: vi.fn(), error: logErrorMock, step: vi.fn(), message: vi.fn() },
}))

const CATALOGUE: ModelsCatalogue = {
  models: [
    { id: 'a-1', label: 'A', ollama: { model: 'a:1b' }, vllm: { model: 'Org/A', args: '--max-model-len=4096' } },
    { id: 'b', label: 'B', ollama: { model: 'b:70b', runtimes: ['gpu-nvidia'] }, vllm: { model: 'Org/B', args: '', runtimes: ['gpu-nvidia'] } },
  ],
}

const CONFIG: Config = { DOMAIN: 'dev.localhost', N8N_VARIANT: 'dev', AI_RUNTIME: 'cpu-arm64', AI_ENGINE: 'ollama', AI_GATEWAY: '', AI_MODELS: '' }

const ENV_CONTENT = `# The domain to run the docker compose services
DOMAIN=dev.localhost
N8N_VARIANT=community
AI_RUNTIME=cpu-arm64
AI_ENGINE=vllm
AI_MODELS=a-1
`

function resources(plan: TiltResources) {
  return plan.projects.flatMap(project => project.resources)
}

function names(plan: TiltResources, filter: (resource: TiltResources['projects'][number]['resources'][number]) => boolean = () => true) {
  return resources(plan).filter(filter).map(resource => resource.name)
}

function find(plan: TiltResources, name: string) {
  const resource = resources(plan).find(resource => resource.name === name)
  expect(resource, name).toBeDefined()
  return resource!
}

let rootDir: string
let logSpy: ReturnType<typeof vi.spyOn>
let previousExitCode: typeof process.exitCode

beforeEach(async () => {
  rootDir = await mkdtemp(join(tmpdir(), 'n8n-starter-tilt-'))
  previousExitCode = process.exitCode
  logErrorMock.mockReset()
  logSpy = vi.spyOn(console, 'log').mockImplementation(() => {})
})

afterEach(async () => {
  logSpy.mockRestore()
  await rm(rootDir, { recursive: true, force: true })
  process.exitCode = previousExitCode
  setLogLevel('info')
})

async function writeCatalogue(catalogue: unknown = CATALOGUE) {
  const dir = join(rootDir, 'compose', 'models')
  await mkdir(dir, { recursive: true })
  await writeFile(join(dir, 'models.json'), JSON.stringify(catalogue))
}

test('dev registers every compose project but enables n8n alone: no storage service, no external task runner', () => {
  const plan = tiltResources(CONFIG, CATALOGUE)

  expect(names(plan, resource => resource.enabled)).toEqual(['docker-socket-proxy', 'traefik', 'qdrant', 'n8n', 'ollama'])
  expect(names(plan, resource => !resource.enabled)).toEqual(['postgres', 'pgadmin', 'redis', 'redisinsight', 'garage', 'garage-webui', 'litellm-db', 'litellm'])
  expect(names(plan)).not.toContain('n8n-runner')
  expect(names(plan)).not.toContain('n8n-worker')
  expect(names(plan)).not.toContain('n8n-webhook')
  // the optional services and the ollama server without models wait for a manual start
  expect(names(plan, resource => !resource.auto_init)).toEqual(['pgadmin', 'redisinsight', 'garage', 'garage-webui', 'qdrant', 'ollama'])
  expect(find(plan, 'n8n')).toMatchObject({ resource_deps: [], links: ['dev.localhost'], infer_links: true })
  expect(find(plan, 'traefik')).toMatchObject({ links: ['traefik.dev.localhost'], infer_links: false })
  expect(find(plan, 'pgadmin')).toMatchObject({ resource_deps: ['postgres'], links: ['pgadmin.dev.localhost'] })
  expect(find(plan, 'garage').links).toEqual(['s3.dev.localhost', 'web.dev.localhost'])
  // the dev variant is the base file alone, only its .env to watch
  const n8n = plan.projects.find(project => project.resources[0]!.service === 'n8n')!
  expect(n8n).toMatchObject({ files: ['./compose/n8n/docker-compose.yml'], watch: ['./compose/n8n/.env'], profiles: [] })
  expect(n8n.project_name).toBeUndefined()
  expect(n8n.override).toBeUndefined()
  expect(plan.config).toEqual({ ...CONFIG, AI_MODELS: [] })
})

test('build enables postgres with pgadmin and the external task runner, neither queue mode nor the enterprise services', () => {
  const plan = tiltResources({ ...CONFIG, N8N_VARIANT: 'build' }, CATALOGUE)

  expect(names(plan, resource => resource.enabled)).toEqual([
    'docker-socket-proxy', 'traefik', 'postgres', 'pgadmin', 'qdrant', 'n8n', 'n8n-runner', 'ollama',
  ])
  expect(names(plan, resource => !resource.enabled)).toEqual(['redis', 'redisinsight', 'garage', 'garage-webui', 'litellm-db', 'litellm'])
  expect(names(plan)).not.toContain('n8n-worker')
  expect(names(plan)).not.toContain('n8n-webhook')
  expect(find(plan, 'n8n')).toMatchObject({ resource_deps: ['postgres'], links: ['dev.localhost'] })
  expect(find(plan, 'n8n-runner').resource_deps).toEqual(['n8n'])
  // the build variant is its own file with the base watched
  const n8n = plan.projects.find(project => project.resources[0]!.service === 'n8n')!
  expect(n8n).toMatchObject({ files: ['./compose/n8n/docker-compose.build.yml'], watch: ['./compose/n8n/docker-compose.yml', './compose/n8n/.env'], profiles: [] })
})

test('community runs queue mode: redis, a worker pair, a webhook processor and n8n waiting for redis', () => {
  const plan = tiltResources({ ...CONFIG, N8N_VARIANT: 'community' }, CATALOGUE)

  expect(names(plan, resource => resource.enabled)).toContain('redis')
  expect(names(plan, resource => resource.enabled)).toContain('redisinsight')
  expect(names(plan, resource => resource.enabled)).not.toContain('garage')
  expect(find(plan, 'n8n').resource_deps).toEqual(['postgres', 'redis'])
  expect(find(plan, 'n8n-worker')).toMatchObject({ labels: ['n8n'], resource_deps: ['n8n', 'redis'], infer_links: false, enabled: true })
  expect(find(plan, 'n8n-worker-runner')).toMatchObject({ resource_deps: ['n8n-worker'], infer_links: false })
  expect(find(plan, 'n8n-webhook')).toMatchObject({ labels: ['n8n'], resource_deps: ['n8n', 'redis'], links: ['hooks.dev.localhost'], infer_links: false, enabled: true })
  const n8n = plan.projects.find(project => project.resources[0]!.service === 'n8n')!
  expect(n8n.files).toEqual(['./compose/n8n/docker-compose.community.yml'])
  expect(n8n.watch).toEqual(['./compose/n8n/docker-compose.yml', './compose/n8n/docker-compose.build.yml', './compose/n8n/.env'])
})

test('enterprise adds garage to queue mode', () => {
  const plan = tiltResources({ ...CONFIG, N8N_VARIANT: 'enterprise' }, CATALOGUE)

  for (const name of ['redis', 'garage', 'garage-webui'])
    expect(find(plan, name).enabled, name).toBe(true)
  expect(names(plan)).toContain('n8n-worker')
  expect(names(plan)).toContain('n8n-webhook')
  const n8n = plan.projects.find(project => project.resources[0]!.service === 'n8n')!
  expect(n8n.files).toEqual([N8N_VARIANT_CASCADE.enterprise.at(-1)])
  expect(n8n.watch).toEqual([...N8N_VARIANT_CASCADE.enterprise.slice(0, -1), './compose/n8n/.env'])
})

test('ollama is one project pulling every selected model, auto-started only with a model', () => {
  const empty = tiltResources(CONFIG, CATALOGUE).projects.at(-1)!
  expect(empty).toMatchObject({
    files: ['./compose/models/ollama/docker-compose.yml'],
    watch: ['./compose/models/ollama/.env'],
    project_name: 'ollama',
    profiles: ['cpu-arm64'],
    override: { services: { 'ollama-cpu-arm64': { environment: { MODELS: '' } } } },
  })
  expect(empty.resources).toEqual([expect.objectContaining({ service: 'ollama-cpu-arm64', name: 'ollama', labels: ['models'], infer_links: false, auto_init: false, enabled: true })])

  const plan = tiltResources({ ...CONFIG, AI_RUNTIME: 'gpu-nvidia', AI_MODELS: 'a-1,b' }, CATALOGUE)
  const ollama = plan.projects.at(-1)!
  expect(ollama.profiles).toEqual(['gpu-nvidia'])
  expect(ollama.override).toEqual({ services: { 'ollama-gpu-nvidia': { environment: { MODELS: 'a:1b,b:70b' } } } })
  expect(ollama.resources[0]).toMatchObject({ service: 'ollama-gpu-nvidia', name: 'ollama', auto_init: true })
  expect(plan.config.AI_MODELS).toEqual(['a-1', 'b'])
})

test('vllm is one project per selected model, named after the id', () => {
  // without a selected model no vllm project exists at all, the gateway project closes the list
  const none = tiltResources({ ...CONFIG, AI_ENGINE: 'vllm' }, CATALOGUE)
  expect(none.projects.at(-1)!.files).toEqual(['./compose/models/litellm/docker-compose.yml'])
  expect(names(none).some(name => name.startsWith('vllm-'))).toBe(false)

  const plan = tiltResources({ ...CONFIG, AI_ENGINE: 'vllm', AI_RUNTIME: 'gpu-nvidia', AI_MODELS: 'a-1,b' }, CATALOGUE)
  const vllm = plan.projects.slice(-2)
  expect(vllm.map(project => project.project_name)).toEqual(['vllm-a-1', 'vllm-b'])
  expect(vllm[0]).toMatchObject({
    files: ['./compose/models/vllm/docker-compose.yml'],
    watch: ['./compose/models/vllm/.env'],
    profiles: ['gpu-nvidia'],
    override: { services: { 'vllm-gpu-nvidia': { container_name: 'vllm-a-1', environment: { MODEL: 'Org/A', MODEL_ARGS: '--max-model-len=4096' } } } },
  })
  expect(vllm[0]!.resources).toEqual([expect.objectContaining({ service: 'vllm-gpu-nvidia', name: 'vllm-a-1', labels: ['models'], infer_links: false, auto_init: true, enabled: true })])
})

test('AI_GATEWAY=litellm enables the gateway with one model list entry per selected model, pointing at the engine', () => {
  // registered but disabled without a gateway, so it stays visible in the Tilt UI
  const off = tiltResources(CONFIG, CATALOGUE)
  expect(find(off, 'litellm').enabled).toBe(false)
  expect(find(off, 'litellm-db').enabled).toBe(false)

  const gateway = (config: Partial<Config>) => {
    const plan = tiltResources({ ...CONFIG, AI_GATEWAY: 'litellm', ...config }, CATALOGUE)
    const project = plan.projects.find(project => project.files[0] === './compose/models/litellm/docker-compose.yml')!
    const override = project.override as { configs: { 'litellm-config': { content: string } }, services: { litellm: { labels: string[] } } }
    expect(Object.keys(override.services)).toEqual(['litellm'])
    return { plan, project, config: JSON.parse(override.configs['litellm-config'].content), labels: override.services.litellm.labels }
  }

  const ollama = gateway({ AI_RUNTIME: 'gpu-nvidia', AI_MODELS: 'a-1,b' })
  expect(ollama.project).toMatchObject({ watch: ['./compose/models/litellm/.env'], profiles: [] })
  expect(ollama.project.project_name).toBeUndefined()
  expect(ollama.project.resources).toEqual([
    expect.objectContaining({ service: 'litellm-db', name: 'litellm-db', labels: ['models'], infer_links: false, auto_init: true, enabled: true }),
    expect.objectContaining({ service: 'litellm', name: 'litellm', labels: ['models'], resource_deps: ['litellm-db'], links: ['litellm.dev.localhost/ui'], auto_init: true, enabled: true }),
  ])
  expect(ollama.config).toEqual({
    model_list: [
      { model_name: 'a-1', litellm_params: { model: 'ollama_chat/a:1b', api_base: 'http://ollama:11434' } },
      { model_name: 'b', litellm_params: { model: 'ollama_chat/b:70b', api_base: 'http://ollama:11434' } },
    ],
  })

  // a vllm model is addressed at its own container, with the key of the vllm containers read from the environment
  const vllm = gateway({ AI_ENGINE: 'vllm', AI_MODELS: 'a-1' })
  expect(vllm.config).toEqual({
    model_list: [
      { model_name: 'a-1', litellm_params: { model: 'hosted_vllm/Org/A', api_base: 'http://vllm-a-1:8000/v1', api_key: 'os.environ/VLLM_API_KEY' } },
    ],
  })
  // the gateway comes before the engine and never waits for a model server
  expect(names(vllm.plan).slice(-3)).toEqual(['litellm-db', 'litellm', 'vllm-a-1'])
  // no model selected, an empty list
  expect(gateway({}).config).toEqual({ model_list: [] })

  // compose and Tilt compare the service, not the content of its config, so the hash of the list labels the proxy:
  // a changed list recreates the container, an unrelated change of the root .env leaves it alone
  expect(ollama.labels).toEqual([expect.stringMatching(new RegExp(`^${GATEWAY_CONFIG_HASH_LABEL}=[0-9a-f]{16}$`))])
  expect(gateway({ AI_RUNTIME: 'gpu-nvidia', AI_MODELS: 'a-1,b', N8N_VARIANT: 'community', DOMAIN: 'other.localhost' }).labels).toEqual(ollama.labels)
  const lists = [ollama, vllm, gateway({}), gateway({ AI_RUNTIME: 'gpu-nvidia', AI_MODELS: 'a-1' }), gateway({ AI_RUNTIME: 'gpu-nvidia', AI_MODELS: 'b,a-1' })]
  expect(new Set(lists.map(list => list.labels[0])).size).toBe(lists.length)
})

test('a project whose directory holds a secrets manifest carries the directory as the filter of its secrets button', () => {
  const secrets = (plan: TiltResources) => plan.projects.filter(project => project.secrets !== undefined).map(project => [project.secrets, project.resources.map(resource => resource.name)])

  expect(secrets(tiltResources(CONFIG, CATALOGUE))).toEqual([])
  expect(secrets(tiltResources({ ...CONFIG, N8N_VARIANT: 'build' }, CATALOGUE, ['compose/n8n', 'compose/storage/postgres', 'compose/unknown']))).toEqual([
    ['compose/storage/postgres', ['postgres']],
    ['compose/n8n', ['n8n', 'n8n-runner']],
  ])
  // every vllm container is a project of the same directory
  expect(secrets(tiltResources({ ...CONFIG, AI_ENGINE: 'vllm', AI_MODELS: 'a-1' }, CATALOGUE, ['compose/models/vllm']))).toEqual([['compose/models/vllm', ['vllm-a-1']]])
})

test('an AI_MODELS id the engine does not serve on the runtime fails listing the served ids', () => {
  // b exists but only on gpu-nvidia, zzz is not in the catalogue
  expect(() => tiltResources({ ...CONFIG, AI_MODELS: 'a-1,b,zzz' }, CATALOGUE))
    .toThrow('AI_MODELS b, zzz: not served by ollama on cpu-arm64, available: a-1')
})

test('the plan schema rejects duplicate names, unknown dependencies and enabled resources depending on disabled ones', () => {
  const plan = tiltResources(CONFIG, CATALOGUE)
  const valid = (candidate: unknown) => tiltResourcesSchema.safeParse(candidate)

  expect(valid(plan).success).toBe(true)
  const duplicate = structuredClone(plan)
  duplicate.projects[0]!.resources[0]!.name = 'traefik'
  expect(valid(duplicate).error?.issues[0]?.message).toContain('Duplicate Tilt resource "traefik"')
  const dangling = structuredClone(plan)
  find(dangling, 'pgadmin').resource_deps = ['nope']
  expect(valid(dangling).error?.issues[0]?.message).toContain('depends on unknown resource "nope"')
  const disabled = structuredClone(plan)
  find(disabled, 'n8n').resource_deps = ['postgres']
  expect(valid(disabled).error?.issues[0]?.message).toContain('Enabled resource "n8n" depends on disabled resource "postgres"')
  // unknown keys and groups are rejected too
  expect(valid({ ...plan, extra: 1 }).success).toBe(false)
  const group = structuredClone(plan)
  group.projects[0]!.resources[0]!.labels = ['edge' as never]
  expect(valid(group).success).toBe(false)
})

test('readRootConfig validates the root .env', async () => {
  await writeFile(join(rootDir, '.env'), ENV_CONTENT)
  // a root .env written before AI_GATEWAY existed runs no gateway
  expect(await readRootConfig(rootDir)).toEqual({ DOMAIN: 'dev.localhost', N8N_VARIANT: 'community', AI_RUNTIME: 'cpu-arm64', AI_ENGINE: 'vllm', AI_GATEWAY: '', AI_MODELS: 'a-1' })

  await writeFile(join(rootDir, '.env'), `${ENV_CONTENT}AI_GATEWAY=litellm\n`)
  expect((await readRootConfig(rootDir)).AI_GATEWAY).toBe('litellm')

  await writeFile(join(rootDir, '.env'), `${ENV_CONTENT}AI_GATEWAY=kong\n`)
  await expect(readRootConfig(rootDir)).rejects.toThrow(/AI_GATEWAY/)

  await writeFile(join(rootDir, '.env'), ENV_CONTENT.replace('N8N_VARIANT=community', 'N8N_VARIANT=pro'))
  await expect(readRootConfig(rootDir)).rejects.toThrow(/Invalid .*\.env:[\s\S]*N8N_VARIANT/)

  await writeFile(join(rootDir, '.env'), 'DOMAIN=dev.localhost\n')
  await expect(readRootConfig(rootDir)).rejects.toThrow(/AI_ENGINE/)

  await rm(join(rootDir, '.env'))
  await expect(readRootConfig(rootDir)).rejects.toThrow('No .env file found')
})

test('tilt resources prints one JSON document and nothing else', async () => {
  await writeFile(join(rootDir, '.env'), ENV_CONTENT)
  await writeCatalogue()
  setLogLevel('error')

  await tilt(rootDir, ['resources'])

  expect(logSpy).toHaveBeenCalledOnce()
  const plan = tiltResourcesSchema.parse(JSON.parse(logSpy.mock.calls[0]![0] as string))
  expect(plan.config).toEqual({ DOMAIN: 'dev.localhost', N8N_VARIANT: 'community', AI_RUNTIME: 'cpu-arm64', AI_ENGINE: 'vllm', AI_GATEWAY: '', AI_MODELS: ['a-1'] })
  expect(names(plan)).toContain('vllm-a-1')
  expect(plan.projects.some(project => project.secrets !== undefined)).toBe(false)
  expect(logErrorMock).not.toHaveBeenCalled()
  expect(process.exitCode).not.toBe(1)
})

test('tilt resources marks the projects with a .env.secrets.json beside their compose file', async () => {
  await writeFile(join(rootDir, '.env'), ENV_CONTENT)
  await writeCatalogue()
  for (const dir of ['compose/n8n', 'compose/models/vllm']) {
    await mkdir(join(rootDir, dir), { recursive: true })
    await writeFile(join(rootDir, dir, '.env.secrets.json'), '{}')
  }
  setLogLevel('error')

  expect(await secretDirectories(rootDir)).toEqual(['compose/models/vllm', 'compose/n8n'])
  await tilt(rootDir, ['resources'])

  const plan = tiltResourcesSchema.parse(JSON.parse(logSpy.mock.calls[0]![0] as string))
  expect(plan.projects.filter(project => project.secrets !== undefined).map(project => [project.secrets, project.resources[0]!.name])).toEqual([
    ['compose/n8n', 'n8n'],
    ['compose/models/vllm', 'vllm-a-1'],
  ])
})

test.each([
  ['a missing .env', async () => { await writeCatalogue() }, 'No .env file found'],
  ['an invalid .env', async () => { await writeCatalogue(); await writeFile(join(rootDir, '.env'), ENV_CONTENT.replace('AI_ENGINE=vllm', 'AI_ENGINE=llamacpp')) }, 'AI_ENGINE'],
  ['a missing catalogue', async () => { await writeFile(join(rootDir, '.env'), ENV_CONTENT) }, 'No model catalogue found'],
  ['an unsupported model', async () => { await writeCatalogue(); await writeFile(join(rootDir, '.env'), ENV_CONTENT.replace('AI_MODELS=a-1', 'AI_MODELS=b')) }, 'AI_MODELS b: not served by vllm on cpu-arm64'],
])('tilt resources fails with %s without printing a plan', async (_, arrange, message) => {
  await arrange()

  await tilt(rootDir, ['resources'])

  expect(logSpy).not.toHaveBeenCalled()
  expect(logErrorMock).toHaveBeenCalledWith(expect.stringContaining(message))
  expect(process.exitCode).toBe(1)
})

test.each([
  [[], 'Missing sub-command for tilt'],
  [['nope'], 'Unknown sub-command "nope" for tilt'],
])('tilt %j fails listing the sub-commands', async (rest, message) => {
  await tilt(rootDir, rest)

  expect(logErrorMock).toHaveBeenCalledWith(expect.stringContaining(message))
  expect(logErrorMock).toHaveBeenCalledWith(expect.stringContaining('resources'))
  expect(process.exitCode).toBe(1)
})

test('the repository catalogue and template defaults produce a valid plan for every variant, engine and gateway', async () => {
  const repoRoot = fileURLToPath(new URL('../../../', import.meta.url))
  const catalogue = await readModelsCatalogue(repoRoot)
  const template = parseEnvContent(await readFile(join(repoRoot, '.env.template'), 'utf-8')) as unknown as Config

  for (const N8N_VARIANT of N8N_VARIANTS) {
    for (const AI_ENGINE of AI_ENGINES) {
      for (const AI_GATEWAY of ['', ...AI_GATEWAYS] as const) {
        const plan = tiltResources({ ...template, N8N_VARIANT, AI_ENGINE, AI_GATEWAY, AI_MODELS: 'qwen3-5-0-8b,qwen3-5-2b' }, catalogue)
        expect(tiltResourcesSchema.safeParse(plan).success).toBe(true)
        // every compose file of the plan exists; the .env files are gitignored, each project watches the one beside its entry file
        for (const file of plan.projects.flatMap(project => [...project.files, ...project.watch.filter(file => !file.endsWith('/.env'))]))
          await expect(readFile(join(repoRoot, file), 'utf-8'), file).resolves.toBeDefined()
        for (const project of plan.projects)
          expect(project.watch.at(-1)).toBe(`${project.files[0]!.replace(/\/[^/]+$/, '')}/.env`)
      }
    }
  }
  // the override of the gateway replaces a config its compose file declares and mounts
  const litellm = await readFile(join(repoRoot, 'compose/models/litellm/docker-compose.yml'), 'utf-8')
  expect(litellm).toMatch(/^configs:\n(?: {2}#.*\n)* {2}litellm-config:\n {4}content:/m)
  expect(litellm).toContain('- source: litellm-config')
  const vllm = tiltResources({ ...template, AI_ENGINE: 'vllm', AI_MODELS: 'qwen3-5-0-8b' }, catalogue)
  expect(names(vllm)).toContain('vllm-qwen3-5-0-8b')
  // every secrets manifest of the repository belongs to a project of the plan, so each of them gets its secrets button
  const secretDirs = await secretDirectories(repoRoot)
  const full = tiltResources({ ...template, N8N_VARIANT: 'enterprise', AI_ENGINE: 'vllm', AI_GATEWAY: 'litellm', AI_MODELS: 'qwen3-5-0-8b' }, catalogue, secretDirs)
  expect([...new Set(full.projects.flatMap(project => project.secrets ?? []))].sort()).toEqual(secretDirs)
  expect(names({ ...full, projects: full.projects.filter(project => project.secrets !== undefined) })).toEqual([
    'postgres', 'pgadmin', 'n8n', 'n8n-runner', 'n8n-worker', 'n8n-worker-runner', 'n8n-webhook', 'litellm-db', 'litellm', 'vllm-qwen3-5-0-8b',
  ])
})
