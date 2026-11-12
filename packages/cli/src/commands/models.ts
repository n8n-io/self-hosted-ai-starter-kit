import type { ModelsCatalogue } from '../schemas/models'
import type { PlatformOptions } from '../utils/platform'
import { readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { isCancel, multiselect } from '@clack/prompts'
import { aiModelsSchema } from '../schemas/config'
import { parseEnvContent, updateEnvContent } from '../utils/env'
import { logger } from '../utils/logger'
import { keyValue, runCommand } from '../utils/format'
import { currentEngineRuntime, currentGateway, formatModelList, listModels, logGatewayEndpoint, logModelEndpoints, modelOptions, modelsCatalogueFile, parseModelList, readModelsCatalogue, unsupportedModels } from '../utils/models'
import { detectPlatform, formatPlatform } from '../utils/platform'

const ENV_FILENAME = '.env'

export const MODELS_SUBCOMMANDS = ['read', 'select'] as const

const CANCELLED = 'Selection cancelled. No changes were made.'

type Current = Record<string, string>

/**
 * The catalogue entries of the engine that run on the runtime: ollama pulls the selected ones into
 * one server, vllm runs one container per selected model (see ../../../../SPEC.md). The docker memory
 * of the platform is shown first so the estimates of the entries can be weighed against it.
 */
async function promptModels(catalogue: ModelsCatalogue, current: Current, docker: PlatformOptions): Promise<string | undefined> {
  const { engine, runtime } = currentEngineRuntime(current)
  const platform = await detectPlatform(docker)
  logger.info(`Detected ${formatPlatform(platform)}`)
  const options = modelOptions(catalogue, engine, runtime, { memory: platform.memory })
  if (options.every(option => option.disabled)) {
    logger.info(`No model of ${engine} runs on ${runtime}, AI_MODELS stays empty`)
    return ''
  }
  const selected = await multiselect<string>({
    message: engine === 'ollama'
      ? 'The models the ollama server pulls on start (none keeps the server available for a manual start)'
      : 'The models to run, one vllm container each',
    options,
    initialValues: parseModelList(current.AI_MODELS ?? '').filter(entry => options.some(option => option.value === entry && !option.disabled)),
    required: false,
  })
  return isCancel(selected) ? undefined : formatModelList(selected)
}

/** Validates an AI_MODELS value given on the command line; returns the error message when it is rejected */
export function validateModels(catalogue: ModelsCatalogue, current: Current, value: string): string | undefined {
  const result = aiModelsSchema.safeParse(value)
  if (!result.success)
    return result.error.issues[0]?.message
  const { engine, runtime } = currentEngineRuntime(current)
  const unsupported = unsupportedModels(catalogue, engine, runtime, parseModelList(value))
  if (unsupported.length > 0)
    return `${unsupported.join(', ')}: not served by ${engine} on ${runtime} (see compose/models/models.json)`
  return undefined
}

/**
 * `models read [filter] [--json]`: the models of the catalogue on stdout, nothing else; one block per engine and
 * model (a header `<engine>/<id>` and `key=value` lines), filtered by a part of an engine or id, or with `json`
 * one array of `{ engine, id, model, label, ... }` in the same order
 */
async function read(rootDir: string, filter: string | undefined, json: boolean): Promise<void> {
  const catalogue = await readModelsCatalogue(rootDir)
  const records = listModels(catalogue, filter)
  if (records.length === 0)
    throw new Error(filter === undefined ? `No model in ${modelsCatalogueFile(rootDir)}` : `No model matches "${filter}", run ${runCommand('models read')} for the list`)
  if (json) {
    console.log(JSON.stringify(records, null, 2))
    return
  }
  const blocks = records.map(({ engine, id, runtimes, ...fields }) => [
    `${engine}/${id}`,
    ...Object.entries(fields).map(([key, value]) => keyValue(key, String(value))),
    ...(runtimes === undefined ? [] : [keyValue('runtimes', runtimes.join(','))]),
  ].join('\n'))
  console.log(blocks.join('\n\n'))
}

/**
 * `models select [ids]`: picks AI_MODELS of the root .env among the catalogue entries of the current
 * engine and runtime, or writes the given comma separated ids without a prompt ("" clears the list).
 * Only AI_MODELS is written; comments and other keys are preserved. `config AI_MODELS` runs it under its own
 * intro, hence `intro`.
 */
async function select(rootDir: string, value: string | undefined, docker: PlatformOptions, intro: boolean): Promise<void> {
  if (intro)
    logger.intro('n8n-starter models select')

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
  const catalogue = await readModelsCatalogue(rootDir)

  let resolved: string | undefined
  if (value !== undefined) {
    const problem = validateModels(catalogue, current, value)
    if (problem !== undefined) {
      logger.error(`Invalid AI_MODELS "${value}": ${problem}`)
      process.exitCode = 1
      return
    }
    resolved = value
  } else {
    resolved = await promptModels(catalogue, current, docker)
  }
  if (resolved === undefined) {
    logger.cancel(CANCELLED)
    return
  }

  await writeFile(envPath, updateEnvContent(content, { AI_MODELS: resolved }))
  logger.success(`AI_MODELS=${resolved}`)
  logModelEndpoints(catalogue, currentEngineRuntime(current).engine, parseModelList(resolved))
  const gateway = currentGateway(current)
  if (gateway !== undefined)
    logGatewayEndpoint(gateway)
  logger.outro(`Configuration written to ${ENV_FILENAME}`)
}

/** `models <read|select> [value] [--json]`, see ../../README.md; `intro: false` leaves the intro of `select` to the caller */
export async function models(rootDir = process.cwd(), [subcommand, value]: string[] = [], { json = false, intro = true }: { json?: boolean, intro?: boolean } = {}, docker: PlatformOptions = {}) {
  if (subcommand !== 'read' && subcommand !== 'select') {
    logger.error(`${subcommand === undefined ? 'Missing' : `Unknown`} sub-command${subcommand === undefined ? '' : ` "${subcommand}"`} for models. Expected one of: ${MODELS_SUBCOMMANDS.join(', ')}`)
    process.exitCode = 1
    return
  }
  try {
    if (subcommand === 'read')
      await read(rootDir, value, json)
    else
      await select(rootDir, value, docker, intro)
  } catch (error) {
    // a missing or invalid catalogue names the file
    logger.error((error as Error).message)
    process.exitCode = 1
  }
}
