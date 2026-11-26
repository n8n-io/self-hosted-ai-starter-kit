import type { AssistantCatalogue } from '../schemas/assistant'
import type { ModelEntry, ModelsCatalogue } from '../schemas/models'
import type { AssistantModel } from '../utils/assistant'
import type { Platform, PlatformOptions } from '../utils/platform'
import { readFile, writeFile } from 'node:fs/promises'
import { join, posix, relative, sep } from 'node:path'
import { styleText } from 'node:util'
import { isCancel, select, text } from '@clack/prompts'
import { z } from 'zod'
import { AI_ENGINES, AI_RUNTIMES, aiEngineSchema, aiGatewaySchema, aiRuntimeSchema, configSchema, domainSchema, N8N_ASSISTANTS, N8N_VARIANTS, n8nAssistantSchema, n8nVariantSchema } from '../schemas/config'
import { activatedModels, ASSISTANT_CATALOGUE_FILE, ASSISTANT_ENV_FILE, ASSISTANT_MODEL_API_KEY, ASSISTANT_MODEL_KEY, ASSISTANT_MODEL_URL_KEY, assistantStaleWarning, assistantTarget, cloudModel, cloudModels, parseCloudModel, readAssistantCatalogue, readAssistantEnv, selfHostedAssistant, writeAssistantModel } from '../utils/assistant'
import { parseEnvContent, updateEnvContent } from '../utils/env'
import { runCommand } from '../utils/format'
import { logger } from '../utils/logger'
import { currentEngineRuntime, currentGateway, logGatewayEndpoint, logModelEndpoints, parseModelList, readModelsCatalogue, unsupportedModels } from '../utils/models'
import { detectPlatform, formatPlatform, runtimeMismatch } from '../utils/platform'
import { models } from './models'
import { checkSecrets, formatSecretCheck, isSecretUnfilled, readSecretState, secretValue } from './secrets'

const ENV_FILENAME = '.env'

/**
 * The keys `config` edits in the root .env, in template order; the descriptions mirror the template comments
 * (see ../../../../.env.template). AI_MODELS is handed to `models select` (see ./models.ts), and N8N_ASSISTANT
 * also writes the model of the Assistant into compose/n8n/.env.
 */
export const CONFIG_KEYS = ['N8N_VARIANT', 'N8N_ASSISTANT', 'AI_RUNTIME', 'AI_ENGINE', 'AI_GATEWAY', 'AI_MODELS', 'DOMAIN'] as const
export type ConfigKey = typeof CONFIG_KEYS[number]
export const configKeySchema = z.enum(CONFIG_KEYS)

export const CONFIG_KEY_DESCRIPTIONS: Record<ConfigKey, string> = {
  N8N_VARIANT: 'Which variant of n8n to run',
  N8N_ASSISTANT: 'The n8n Assistant with its sandbox and web search',
  AI_RUNTIME: 'The hardware supported ai runtime',
  AI_ENGINE: 'The engine serving the AI models',
  AI_GATEWAY: 'The gateway in front of the AI models',
  AI_MODELS: 'The models of ./compose/models/models.json that start with the stack',
  DOMAIN: 'The domain to run the docker compose services',
}

const CANCELLED = 'Configuration cancelled. No changes were made.'

/** How an empty value reads in a prompt and a hint: AI_GATEWAY offers it as its first option */
const NONE = 'none'

type Current = Record<string, string>

const CHOICES = {
  N8N_VARIANT: { message: 'Which variant of n8n to run', options: N8N_VARIANTS, schema: n8nVariantSchema },
  N8N_ASSISTANT: { message: 'Run the n8n Assistant with its sandbox and web search', options: N8N_ASSISTANTS, schema: n8nAssistantSchema },
  AI_RUNTIME: { message: 'The hardware-supported AI runtime', options: AI_RUNTIMES, schema: aiRuntimeSchema },
  AI_ENGINE: { message: 'The engine serving the AI models', options: AI_ENGINES, schema: aiEngineSchema },
  AI_GATEWAY: { message: 'The gateway in front of the AI models', options: aiGatewaySchema.options, schema: aiGatewaySchema },
} as const

/**
 * The hint of a key in the key select: its description, then the available values with the current
 * one in green (styleText stays plain without a tty or with NO_COLOR). DOMAIN and AI_MODELS have no list,
 * only their current value; the empty option of AI_GATEWAY and an empty AI_MODELS read `none`.
 */
export function keyHint(key: ConfigKey, current: Current): string {
  const selected = current[key] ?? ''
  const available: readonly string[] = key === 'DOMAIN' || key === 'AI_MODELS' ? [selected] : CHOICES[key].options
  const values = [...new Set([...available, selected])].filter(value => value !== '' || available.includes(''))
  const rendered = values.map(value => value === selected ? styleText('green', value || NONE) : value || NONE)
  return `${CONFIG_KEY_DESCRIPTIONS[key]}: ${rendered.length > 0 ? rendered.join(', ') : NONE}`
}

async function promptKey(current: Current): Promise<ConfigKey | undefined> {
  const key = await select<ConfigKey>({
    message: 'Which setting to configure',
    options: CONFIG_KEYS.map(value => ({ value, label: value, hint: keyHint(value, current) })),
  })
  return isCancel(key) ? undefined : key
}

async function promptDomain(current: Current): Promise<string | undefined> {
  const domain = await text({
    message: 'The domain to run the Docker Compose services on',
    initialValue: current.DOMAIN ?? 'n8n.localhost',
    validate: value => domainSchema.safeParse(value).error?.issues[0]?.message,
  })
  return isCancel(domain) ? undefined : domain
}

/**
 * The option equal to `detected` (the runtime of the platform) carries a green `(detected)` in its label, so it
 * stays visible on every row (clack shows a `hint` on the focused row only; an inactive label is dimmed, which
 * keeps the green); the current value stays preselected
 */
async function promptChoice(key: keyof typeof CHOICES, current: Current, detected?: string): Promise<string | undefined> {
  const { message, options, schema } = CHOICES[key]
  const value = await select<string>({
    message,
    options: options.map(value => ({ value, label: value === detected ? `${value} ${styleText('green', '(detected)')}` : value || NONE })),
    initialValue: schema.safeParse(current[key]).data,
  })
  return isCancel(value) ? undefined : value
}

/** A cloud model or a model of AI_MODELS, as `config N8N_ASSISTANT` writes it into compose/n8n/.env */
type AssistantSelection = AssistantModel & { kind: 'cloud' | 'self-hosted' }

/** What N8N_ASSISTANT starts beside n8n, see ../../../../compose/n8n/assistant/docker-compose.yml */
const ASSISTANT_SERVICES = 'sandbox-api, sandbox-runner-1 and searxng of compose/n8n/assistant'

/** The models of AI_MODELS the Assistant can use with the engine and runtime of a root .env */
function assistantCandidates(catalogue: ModelsCatalogue, current: Current): ModelEntry[] {
  const { engine, runtime } = currentEngineRuntime(current)
  return activatedModels(catalogue, engine, runtime, parseModelList(current.AI_MODELS ?? ''))
}

/**
 * The prompts of an activation: a cloud provider or a model of AI_MODELS, then the provider and one of its
 * recommended models (see ../../../../compose/models/models.cloud.json), or one of the activated models.
 * The current model stays preselected; self-hosted is disabled while AI_MODELS lists no model of the engine.
 */
async function promptAssistantModel(models: ModelsCatalogue, providers: AssistantCatalogue, current: Current, rootDir: string): Promise<AssistantSelection | undefined> {
  const { engine, runtime } = currentEngineRuntime(current)
  const candidates = assistantCandidates(models, current)
  const env = await readAssistantEnv(rootDir)
  const target = assistantTarget(models, engine, runtime, parseModelList(current.AI_MODELS ?? ''), env)

  const source = await select<AssistantSelection['kind']>({
    message: 'The model of the n8n Assistant',
    options: [
      { value: 'cloud', label: 'cloud provider', hint: providers.providers.map(provider => provider.label).join(', ') },
      {
        value: 'self-hosted',
        label: `self-hosted on ${engine}`,
        hint: candidates.length > 0 ? candidates.map(entry => entry.id).join(', ') : `no model of AI_MODELS runs on ${engine}, run ${runCommand('models select')}`,
        disabled: candidates.length === 0,
      },
    ],
    initialValue: target.kind === 'self-hosted' ? 'self-hosted' : 'cloud',
  })
  if (isCancel(source))
    return undefined

  if (source === 'self-hosted') {
    const id = await select<string>({
      message: `The model of AI_MODELS, served by ${engine}`,
      options: candidates.map(entry => ({ value: entry.id, label: entry.id, hint: `${entry.label}, ${entry.model}` })),
      initialValue: target.kind === 'self-hosted' ? target.id : undefined,
    })
    if (isCancel(id))
      return undefined
    return { kind: 'self-hosted', ...selfHostedAssistant(candidates.find(entry => entry.id === id)!, engine) }
  }

  const held = target.kind === 'cloud' && env.model !== undefined ? parseCloudModel(env.model) : undefined
  const providerId = await select<string>({
    message: 'The cloud provider',
    options: providers.providers.map(provider => ({ value: provider.id, label: provider.label, hint: provider.models.map(model => model.label).join(', ') })),
    initialValue: providers.providers.find(provider => provider.id === held?.provider)?.id,
  })
  if (isCancel(providerId))
    return undefined
  const provider = providers.providers.find(candidate => candidate.id === providerId)!
  const modelId = await select<string>({
    message: `The model of ${provider.label}`,
    options: provider.models.map(model => ({ value: model.id, label: model.label, hint: [cloudModel(provider.id, model.id), model.note].filter(Boolean).join(', ') })),
    initialValue: provider.models.find(model => model.id === held?.model)?.id,
  })
  if (isCancel(modelId))
    return undefined
  return { kind: 'cloud', model: cloudModel(provider.id, modelId), url: '' }
}

/**
 * A model given on the command line: an id of AI_MODELS the engine serves on the runtime, or `provider/model`,
 * which is accepted with a warning when the cloud catalogue does not list it. Throws with the reason otherwise.
 */
async function resolveAssistantModel(rootDir: string, current: Current, model: string): Promise<AssistantSelection> {
  if (model.includes('/')) {
    const providers = await readAssistantCatalogue(rootDir)
    if (parseCloudModel(model) === undefined)
      throw new Error(`Invalid model "${model}": expected an id of AI_MODELS or provider/model such as ${cloudModels(providers)[0]}`)
    if (!cloudModels(providers).includes(model))
      logger.warn(`${model} is not one of the recommended models of ${ASSISTANT_CATALOGUE_FILE}`)
    return { kind: 'cloud', model, url: '' }
  }
  const { engine, runtime } = currentEngineRuntime(current)
  const entry = assistantCandidates(await readModelsCatalogue(rootDir), current).find(candidate => candidate.id === model)
  if (entry === undefined)
    throw new Error(`Invalid model "${model}": not a model of AI_MODELS served by ${engine} on ${runtime}, run ${runCommand('models select')} or name a cloud model as provider/model`)
  return { kind: 'self-hosted', ...selfHostedAssistant(entry, engine) }
}

/**
 * The command that gives n8n the key its model needs, or undefined: a cloud provider needs the key of the account
 * (which the Assistant settings of n8n take as well), vllm its bearer token, ollama none. Both are secrets, so
 * `config` names the command and never writes one.
 */
async function assistantKeyHint(rootDir: string, kind: string, engine: string): Promise<{ warn: boolean, message: string } | undefined> {
  const state = await readSecretState(rootDir)
  const declared = (dir: string, key: string) => state.declared.find(candidate => relative(rootDir, candidate.dir).split(sep).join('/') === dir && candidate.key === key)
  const value = (secret: ReturnType<typeof declared>) => secret === undefined || isSecretUnfilled(state, secret) ? undefined : secretValue(state, secret)
  const modelKey = declared(posix.dirname(ASSISTANT_ENV_FILE), ASSISTANT_MODEL_API_KEY)
  // `secrets set` only writes a key the manifest of compose/n8n declares
  if (modelKey === undefined)
    return undefined
  const key = value(modelKey)
  const bearer = value(declared('compose/models/vllm', 'VLLM_API_KEY'))
  if (kind === 'cloud' && (key === undefined || key === bearer))
    return { warn: false, message: `Set the key of the provider with ${runCommand(`secrets set ${ASSISTANT_MODEL_API_KEY}`)}, or in the Assistant settings of n8n` }
  if (kind === 'self-hosted' && engine === 'vllm' && (key === undefined || key !== bearer))
    // `secrets read KEY` prints one line per manifest that declares the key, and the gateway links this one too
    return { warn: true, message: `vllm needs its bearer token as ${ASSISTANT_MODEL_API_KEY}, run ${runCommand(`secrets set ${ASSISTANT_MODEL_API_KEY} "$(pnpm --silent run secrets read VLLM_API_KEY | head -n 1)"`)}` }
  return undefined
}

/**
 * What an activated Assistant runs on and what it still needs: the model n8n reads from compose/n8n/.env, the
 * services the toggle starts, a model the engine no longer serves and the key of its endpoint. A missing or invalid
 * catalogue or manifest only costs the last two.
 */
async function reportAssistant(rootDir: string, updated: Current, selection: AssistantSelection | undefined) {
  const held = await readAssistantEnv(rootDir)
  const model = selection?.model ?? held.model
  const url = selection === undefined ? held.url : selection.url || undefined
  logger.info(model === undefined
    ? `The Assistant uses the default model of compose/n8n/docker-compose.yml, run ${runCommand('config N8N_ASSISTANT')} to pick one`
    : `The Assistant uses ${model}${url === undefined ? '' : ` at ${url}`} (${ASSISTANT_MODEL_KEY}${url === undefined ? '' : ` and ${ASSISTANT_MODEL_URL_KEY}`} of ${ASSISTANT_ENV_FILE})`)
  logger.info(`It starts ${ASSISTANT_SERVICES}; the sandbox runner is a privileged container, for development and testing only`)
  try {
    const { engine, runtime } = currentEngineRuntime(updated)
    const target = assistantTarget(await readModelsCatalogue(rootDir), engine, runtime, parseModelList(updated.AI_MODELS ?? ''), { model, url })
    if (target.kind === 'stale')
      logger.warn(`${target.reason}, run ${runCommand('config N8N_ASSISTANT')}`)
    const hint = await assistantKeyHint(rootDir, target.kind, engine)
    if (hint !== undefined)
      logger[hint.warn ? 'warn' : 'info'](hint.message)
  } catch (error) {
    logger.warn((error as Error).message)
  }
}

/**
 * A variant, engine, runtime or the Assistant can require a secret: a human one (the enterprise license) is pointed
 * at, never prompted for here, and a link the new value needs is filled by `setup`; an invalid root .env or
 * manifest only costs this check
 */
async function warnSecrets(rootDir: string, updated: Current) {
  const config = configSchema.safeParse(updated)
  if (!config.success)
    return
  try {
    for (const check of checkSecrets(await readSecretState(rootDir), config.data)) {
      if (check.status === 'required')
        logger.warn(formatSecretCheck(rootDir, check))
      else if (check.status === 'missing' && check.condition !== undefined)
        logger.warn(`${formatSecretCheck(rootDir, check)}, run ${runCommand('setup')}`)
    }
  } catch (error) {
    logger.warn((error as Error).message)
  }
}

/**
 * `config N8N_ASSISTANT [value] [model]`: the toggle of the root .env and, on activation, the model of the
 * Assistant in compose/n8n/.env (see ../../../../SPEC.md). Without a value it asks for both, `true <model>`
 * writes both without a prompt, and `true` or `false` alone only flips the toggle and keeps the model the file
 * holds. The model is written first, so a failure leaves the Assistant off.
 */
async function configAssistant(rootDir: string, envPath: string, content: string, current: Current, value: string | undefined, model: string | undefined) {
  let enabled: string | undefined
  if (value !== undefined) {
    const result = n8nAssistantSchema.safeParse(value)
    if (!result.success) {
      logger.error(`Invalid N8N_ASSISTANT "${value}": ${result.error.issues[0]?.message}`)
      process.exitCode = 1
      return
    }
    enabled = value
  } else {
    enabled = await promptChoice('N8N_ASSISTANT', current)
  }
  if (enabled === undefined) {
    logger.cancel(CANCELLED)
    return
  }

  let selection: AssistantSelection | undefined
  try {
    if (model !== undefined) {
      if (enabled !== 'true')
        throw new Error(`A model is only given with N8N_ASSISTANT true, not with "${enabled}"`)
      selection = await resolveAssistantModel(rootDir, current, model)
    } else if (enabled === 'true' && value === undefined) {
      selection = await promptAssistantModel(await readModelsCatalogue(rootDir), await readAssistantCatalogue(rootDir), current, rootDir)
      if (selection === undefined) {
        logger.cancel(CANCELLED)
        return
      }
    }
    if (selection !== undefined)
      await writeAssistantModel(rootDir, selection)
  } catch (error) {
    // a missing catalogue or compose/n8n/.env names the file, a rejected model the reason
    logger.error((error as Error).message)
    process.exitCode = 1
    return
  }

  await writeFile(envPath, updateEnvContent(content, { N8N_ASSISTANT: enabled }))
  logger.success(`N8N_ASSISTANT=${enabled}`)

  const updated = { ...current, N8N_ASSISTANT: enabled }
  if (enabled === 'true')
    await reportAssistant(rootDir, updated, selection)
  await warnSecrets(rootDir, updated)

  logger.outro(selection === undefined ? `Configuration written to ${ENV_FILENAME}` : `Configuration written to ${ENV_FILENAME} and ${ASSISTANT_ENV_FILE}`)
}

/**
 * Edits one key of the root .env: `config` asks which, `config KEY` prompts that key only and
 * `config KEY value` writes without a prompt. Only the requested key is written; comments,
 * blank lines and other keys are preserved. AI_RUNTIME detects the platform (see ../utils/platform.ts)
 * to mark the fitting option and to warn about a value that differs from it. AI_MODELS runs
 * `models select [value]` (see ./models.ts): its multi-select, or its validation of the given ids.
 * N8N_ASSISTANT takes a model as third argument and also writes it into compose/n8n/.env.
 */
export async function config(rootDir = process.cwd(), [requestedKey, value, model]: string[] = [], docker: PlatformOptions = {}) {
  logger.intro('n8n-starter config')

  const envPath = join(rootDir, ENV_FILENAME)
  let content: string
  try {
    content = await readFile(envPath, 'utf-8')
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT')
      throw error
    logger.error(`No ${ENV_FILENAME} file found in ${rootDir}. Run ${runCommand('setup')} first.`)
    process.exitCode = 1
    return
  }
  const current = parseEnvContent(content)

  let key: ConfigKey
  if (requestedKey === undefined) {
    const selected = await promptKey(current)
    if (selected === undefined) {
      logger.cancel(CANCELLED)
      return
    }
    key = selected
  } else {
    const parsed = configKeySchema.safeParse(requestedKey)
    if (!parsed.success) {
      logger.error(`Unknown config key "${requestedKey}". Expected one of: ${CONFIG_KEYS.join(', ')}`)
      process.exitCode = 1
      return
    }
    key = parsed.data
  }

  // the models have their own command: the catalogue multi-select, or the ids validated against it
  if (key === 'AI_MODELS')
    return models(rootDir, value === undefined ? ['select'] : ['select', value], { intro: false }, docker)

  // the Assistant is a toggle of the root .env plus its model in compose/n8n/.env
  if (key === 'N8N_ASSISTANT')
    return configAssistant(rootDir, envPath, content, current, value, model)

  // only the runtime key asks docker what the machine is here; the other keys never touch it
  let platform: Platform | undefined
  if (key === 'AI_RUNTIME') {
    platform = await detectPlatform(docker)
    logger.info(`Detected ${formatPlatform(platform)}`)
  }

  let resolved: string | undefined
  if (value !== undefined) {
    const result = configSchema.shape[key].safeParse(value)
    if (!result.success) {
      logger.error(`Invalid ${key} "${value}": ${result.error.issues[0]?.message}`)
      process.exitCode = 1
      return
    }
    resolved = value
  } else if (key === 'DOMAIN') {
    resolved = await promptDomain(current)
  } else {
    resolved = await promptChoice(key, current, platform?.runtime)
  }
  if (resolved === undefined) {
    logger.cancel(CANCELLED)
    return
  }

  await writeFile(envPath, updateEnvContent(content, { [key]: resolved }))
  logger.success(`${key}=${resolved}`)

  const updated = { ...current, [key]: resolved }

  if (platform !== undefined) {
    const mismatch = runtimeMismatch(platform, aiRuntimeSchema.parse(resolved))
    if (mismatch !== undefined)
      logger.warn(mismatch)
  }

  // an engine or runtime change can leave AI_MODELS ids behind that the new combination does not serve:
  // they are kept and reported; a missing or invalid catalogue only costs this check
  if (key === 'AI_ENGINE' || key === 'AI_RUNTIME') {
    const { engine, runtime } = currentEngineRuntime(updated)
    const models = parseModelList(updated.AI_MODELS ?? '')
    let catalogue: ModelsCatalogue | undefined
    try {
      catalogue = await readModelsCatalogue(rootDir)
    } catch (error) {
      logger.warn((error as Error).message)
    }
    if (catalogue) {
      if (key === 'AI_ENGINE')
        logModelEndpoints(catalogue, engine, models)
      const stale = unsupportedModels(catalogue, engine, runtime, models)
      if (stale.length > 0)
        logger.warn(`AI_MODELS=${updated.AI_MODELS}: ${stale.join(', ')} not served by ${engine} on ${runtime}, run ${runCommand('models select')}`)
      // the Assistant keeps the endpoint of the engine it was activated with
      const staleAssistant = await assistantStaleWarning(rootDir, updated, catalogue)
      if (staleAssistant !== undefined)
        logger.warn(staleAssistant)
    }
  }

  if (key === 'AI_GATEWAY') {
    const gateway = currentGateway(updated)
    if (gateway !== undefined)
      logGatewayEndpoint(gateway)
  }

  if (key !== 'DOMAIN')
    await warnSecrets(rootDir, updated)

  logger.outro(`Configuration written to ${ENV_FILENAME}`)
}
