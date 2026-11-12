import type { ModelsCatalogue } from '../schemas/models'
import type { Platform, PlatformOptions } from '../utils/platform'
import { readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { styleText } from 'node:util'
import { isCancel, select, text } from '@clack/prompts'
import { z } from 'zod'
import { AI_ENGINES, AI_RUNTIMES, aiEngineSchema, aiGatewaySchema, aiRuntimeSchema, configSchema, domainSchema, N8N_VARIANTS, n8nVariantSchema } from '../schemas/config'
import { parseEnvContent, updateEnvContent } from '../utils/env'
import { runCommand } from '../utils/format'
import { logger } from '../utils/logger'
import { currentEngineRuntime, currentGateway, logGatewayEndpoint, logModelEndpoints, parseModelList, readModelsCatalogue, unsupportedModels } from '../utils/models'
import { detectPlatform, formatPlatform, runtimeMismatch } from '../utils/platform'
import { models } from './models'
import { checkSecrets, formatSecretCheck, readSecretState } from './secrets'

const ENV_FILENAME = '.env'

/**
 * The keys `config` edits in the root .env, in template order; the descriptions mirror the template comments
 * (see ../../../../.env.template). AI_MODELS is handed to `models select` (see ./models.ts).
 */
export const CONFIG_KEYS = ['N8N_VARIANT', 'AI_RUNTIME', 'AI_ENGINE', 'AI_GATEWAY', 'AI_MODELS', 'DOMAIN'] as const
export type ConfigKey = typeof CONFIG_KEYS[number]
export const configKeySchema = z.enum(CONFIG_KEYS)

export const CONFIG_KEY_DESCRIPTIONS: Record<ConfigKey, string> = {
  N8N_VARIANT: 'Which variant of n8n to run',
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

/**
 * Edits one key of the root .env: `config` asks which, `config KEY` prompts that key only and
 * `config KEY value` writes without a prompt. Only the requested key is written; comments,
 * blank lines and other keys are preserved. AI_RUNTIME detects the platform (see ../utils/platform.ts)
 * to mark the fitting option and to warn about a value that differs from it. AI_MODELS runs
 * `models select [value]` (see ./models.ts): its multi-select, or its validation of the given ids.
 */
export async function config(rootDir = process.cwd(), [requestedKey, value]: string[] = [], docker: PlatformOptions = {}) {
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
    }
  }

  if (key === 'AI_GATEWAY') {
    const gateway = currentGateway(updated)
    if (gateway !== undefined)
      logGatewayEndpoint(gateway)
  }

  // a variant, engine or runtime can require a human secret (the enterprise license): it is pointed at,
  // never prompted for here; an invalid root .env or manifest only costs this check
  if (key !== 'DOMAIN') {
    const config = configSchema.safeParse(updated)
    if (config.success) {
      try {
        for (const check of checkSecrets(await readSecretState(rootDir), config.data)) {
          if (check.status === 'required')
            logger.warn(formatSecretCheck(rootDir, check))
        }
      } catch (error) {
        logger.warn((error as Error).message)
      }
    }
  }

  logger.outro(`Configuration written to ${ENV_FILENAME}`)
}
