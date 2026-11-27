import type { AiEngine, AiGateway, AiRuntime } from '../schemas/config'
import type { ModelEntry, ModelsCatalogue } from '../schemas/models'
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { styleText } from 'node:util'
import { z } from 'zod'
import { AI_ENGINES, AI_RUNTIMES, aiEngineSchema, aiGatewaySchema, aiRuntimeSchema } from '../schemas/config'
import { modelsCatalogueSchema } from '../schemas/models'
import { logger } from './logger'

export interface ModelOption {
  value: string
  label: string
  hint?: string
  disabled?: boolean
}

/** One model as one engine serves it, the record `models read` prints: engine and id first, then the fields of the entry */
export interface ModelRecord {
  engine: AiEngine
  id: string
  model: string
  label: string
  args?: string
  memory?: number
  note?: string
  runtimes?: AiRuntime[]
}

/** The model catalogue of every engine, see ../../../../SPEC.md */
export function modelsCatalogueFile(rootDir: string): string {
  return join(rootDir, 'compose', 'models', 'models.json')
}

/** The validated catalogue; throws naming the file when it is missing or invalid */
export async function readModelsCatalogue(rootDir: string): Promise<ModelsCatalogue> {
  const file = modelsCatalogueFile(rootDir)
  let content: string
  try {
    content = await readFile(file, 'utf-8')
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT')
      throw error
    throw new Error(`No model catalogue found at ${file}`)
  }
  const result = modelsCatalogueSchema.safeParse(JSON.parse(content))
  if (!result.success)
    throw new Error(`Invalid model catalogue ${file}:\n${z.prettifyError(result.error)}`)
  return result.data
}

/** The models the engine serves, each flattened to its id and label plus the fields of the engine's block, in catalogue order */
export function engineEntries(catalogue: ModelsCatalogue, engine: AiEngine): ModelEntry[] {
  return catalogue.models.flatMap((model) => {
    const serving = model[engine]
    return serving === undefined ? [] : [{ id: model.id, label: model.label, ...serving }]
  })
}

export function runsOn(entry: ModelEntry, runtime: AiRuntime): boolean {
  return (entry.runtimes ?? AI_RUNTIMES).includes(runtime)
}

/** The entries of the engine that run on the runtime (every runtime unless the entry lists some) */
export function modelEntries(catalogue: ModelsCatalogue, engine: AiEngine, runtime: AiRuntime): ModelEntry[] {
  return engineEntries(catalogue, engine).filter(entry => runsOn(entry, runtime))
}

/**
 * The records of every engine, engines in AI_ENGINES order and models in catalogue order, keeping those
 * whose engine or id contains `filter` (case-insensitive); the fields of an entry follow engine and id
 */
export function listModels(catalogue: ModelsCatalogue, filter = ''): ModelRecord[] {
  const needle = filter.toLowerCase()
  return AI_ENGINES.flatMap(engine => engineEntries(catalogue, engine).map((entry): ModelRecord => ({
    engine,
    id: entry.id,
    model: entry.model,
    label: entry.label,
    ...('args' in entry ? { args: entry.args } : {}),
    ...(entry.memory === undefined ? {} : { memory: entry.memory }),
    ...(entry.note === undefined ? {} : { note: entry.note }),
    ...(entry.runtimes === undefined ? {} : { runtimes: entry.runtimes }),
  }))).filter(record => record.engine.includes(needle) || record.id.toLowerCase().includes(needle))
}

/** The engine and runtime of a root .env, falling back to the defaults when unset or invalid */
export function currentEngineRuntime(current: Record<string, string>): { engine: AiEngine, runtime: AiRuntime } {
  return {
    engine: aiEngineSchema.safeParse(current.AI_ENGINE).data ?? AI_ENGINES[0],
    runtime: aiRuntimeSchema.safeParse(current.AI_RUNTIME).data ?? AI_RUNTIMES[0],
  }
}

/** The ids of `models` that the engine does not serve on the runtime */
export function unsupportedModels(catalogue: ModelsCatalogue, engine: AiEngine, runtime: AiRuntime, models: string[]): string[] {
  const served = new Set(modelEntries(catalogue, engine, runtime).map(entry => entry.id))
  return models.filter(id => !served.has(id))
}

/** The catalogue `memory` (an estimate in GB) with the unit of the runtime: `~6 GB RAM`, or VRAM on a gpu runtime */
export function formatMemory(memory: number, runtime: AiRuntime): string {
  return `~${memory} GB ${runtime.startsWith('gpu-') ? 'VRAM' : 'RAM'}`
}

export interface ModelOptionLimits {
  /** The memory of the Docker VM in GB (see ./platform.ts); an estimate above it is pointed out on the cpu runtimes */
  memory?: number
}

/**
 * Every entry of the engine as prompt option: the id is the AI_MODELS value, the hint shows what it is and
 * what it needs, and an entry the runtime cannot run stays visible but disabled, with the reason in yellow
 * (styleText keeps the hint plain without a tty or with NO_COLOR, like the prompt itself). On a cpu runtime an
 * estimate above the docker memory is pointed out in yellow too, but stays selectable: the estimate is a guard,
 * not a limit (see ../../../../SPEC.md), and the VRAM of a gpu is unknown here.
 */
export function modelOptions(catalogue: ModelsCatalogue, engine: AiEngine, runtime: AiRuntime, { memory }: ModelOptionLimits = {}): ModelOption[] {
  return engineEntries(catalogue, engine).map((entry) => {
    const runs = runsOn(entry, runtime)
    const over = memory !== undefined && entry.memory !== undefined && !runtime.startsWith('gpu-') && entry.memory > memory
    return {
      value: entry.id,
      label: entry.id,
      hint: [
        entry.label,
        entry.model,
        entry.memory !== undefined && formatMemory(entry.memory, runtime),
        over && styleText('yellow', `over the ${memory} GB of docker memory`),
        entry.note,
        !runs && styleText('yellow', `not on ${runtime}`),
      ].filter(Boolean).join(', '),
      disabled: !runs,
    }
  })
}

/**
 * The docker name of a vllm model (Tilt resource, compose project, container and hostname), from the id of
 * its catalogue entry; mirrors `container_name: vllm-${VLLM_MODEL_ID:-model}` in compose/models/vllm/docker-compose.yml
 */
export function vllmContainerName(id: string): string {
  return `vllm-${id}`
}

/** Where n8n reaches a vllm model on n8n-starter-private, see ../../../../SPEC.md */
export function vllmEndpoint(id: string): string {
  return `http://${vllmContainerName(id)}:8000/v1`
}

/** Where n8n reaches the ollama server on n8n-starter-private, see ../../../../SPEC.md */
export const OLLAMA_ENDPOINT = 'http://ollama:11434'

/**
 * Where n8n reaches a gateway on n8n-starter-private (one OpenAI compatible endpoint for every model of AI_MODELS) and the
 * key of compose/models/<gateway>/.env it sends as bearer token, see ../../../../SPEC.md
 */
export const GATEWAYS: Record<AiGateway, { endpoint: string, key: string }> = {
  litellm: { endpoint: 'http://litellm:4000/v1', key: 'LITELLM_MASTER_KEY' },
}

/** The gateway of a root .env, undefined when none is set or the value is invalid */
export function currentGateway(current: Record<string, string>): AiGateway | undefined {
  return aiGatewaySchema.safeParse(current.AI_GATEWAY).data || undefined
}

/** Logs where n8n reaches the models through the gateway (see ../../../../SPEC.md) */
export function logGatewayEndpoint(gateway: AiGateway) {
  const { endpoint, key } = GATEWAYS[gateway]
  logger.info(`${gateway} serves every model of AI_MODELS under its id at ${endpoint}, bearer token ${key} of compose/models/${gateway}/.env`)
}

/** Logs where n8n reaches the selected models on n8n-starter-private (see ../../../../SPEC.md) */
export function logModelEndpoints(catalogue: ModelsCatalogue, engine: AiEngine, models: string[]) {
  if (engine === 'ollama') {
    logger.info(`ollama serves every pulled model at ${OLLAMA_ENDPOINT}`)
    return
  }
  const served = new Set(engineEntries(catalogue, 'vllm').map(entry => entry.id))
  for (const id of models) {
    if (served.has(id))
      logger.info(`${id} runs at ${vllmEndpoint(id)}, bearer token VLLM_API_KEY of compose/models/vllm/.env`)
  }
}

/** AI_MODELS is a comma separated list, `a, b,` reads as ['a', 'b'] */
export function parseModelList(value: string): string[] {
  return value.split(',').map(entry => entry.trim()).filter(entry => entry !== '')
}

export function formatModelList(entries: string[]): string {
  return entries.join(',')
}
