import type { AssistantCatalogue } from '../schemas/assistant'
import type { AiEngine, AiRuntime } from '../schemas/config'
import type { ModelEntry, ModelsCatalogue } from '../schemas/models'
import { readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { z } from 'zod'
import { ASSISTANT_MODEL_ID_PATTERN, ASSISTANT_PROVIDER_ID_PATTERN, assistantCatalogueSchema } from '../schemas/assistant'
import { parseEnvContent, updateEnvContent } from './env'
import { runCommand } from './format'
import { currentEngineRuntime, modelEntries, OLLAMA_ENDPOINT, parseModelList, vllmContainerName, vllmEndpoint } from './models'

/** The n8n settings `config N8N_ASSISTANT` writes into compose/n8n/.env, and the key a cloud provider or vllm needs beside them (see ../../../../SPEC.md) */
export const ASSISTANT_MODEL_KEY = 'N8N_INSTANCE_AI_MODEL'
export const ASSISTANT_MODEL_URL_KEY = 'N8N_INSTANCE_AI_MODEL_URL'
export const ASSISTANT_MODEL_API_KEY = 'N8N_INSTANCE_AI_MODEL_API_KEY'

/** The .env of the n8n compose project, relative to the root: where the model of the Assistant lives */
export const ASSISTANT_ENV_FILE = 'compose/n8n/.env'
/** The cloud models `config N8N_ASSISTANT` offers, relative to the root */
export const ASSISTANT_CATALOGUE_FILE = 'compose/models/models.assistant.json'

/** The OpenAI compatible endpoint of the ollama server, which n8n needs as the base URL of a custom model */
export const OLLAMA_OPENAI_ENDPOINT = `${OLLAMA_ENDPOINT}/v1`

/** The model of the Assistant as compose/n8n/.env holds it; a key that is absent or empty is undefined */
export interface AssistantEnv {
  model?: string
  url?: string
}

/** The two values of a model: `url` is empty for a cloud model, which n8n addresses at its provider */
export interface AssistantModel {
  model: string
  url: string
}

/** What the model of compose/n8n/.env points at: a cloud provider, a model of AI_MODELS, an endpoint of your own, or a kit model server that no longer serves it */
export type AssistantTarget
  = | { kind: 'cloud' }
    | { kind: 'self-hosted', id: string }
    | { kind: 'custom' }
    | { kind: 'stale', reason: string }

/** The validated cloud catalogue; throws naming the file when it is missing or invalid */
export async function readAssistantCatalogue(rootDir: string): Promise<AssistantCatalogue> {
  const file = join(rootDir, ASSISTANT_CATALOGUE_FILE)
  let content: string
  try {
    content = await readFile(file, 'utf-8')
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT')
      throw error
    throw new Error(`No assistant model catalogue found at ${file}`)
  }
  const result = assistantCatalogueSchema.safeParse(JSON.parse(content))
  if (!result.success)
    throw new Error(`Invalid assistant model catalogue ${file}:\n${z.prettifyError(result.error)}`)
  return result.data
}

/** A cloud model as n8n reads it: the provider, a slash, the name of the model there */
export function cloudModel(provider: string, model: string): string {
  return `${provider}/${model}`
}

/** Every model of the catalogue as an N8N_INSTANCE_AI_MODEL value, in catalogue order: the first one is the default of the compose file */
export function cloudModels(catalogue: AssistantCatalogue): string[] {
  return catalogue.providers.flatMap(provider => provider.models.map(model => cloudModel(provider.id, model.id)))
}

/** Splits `provider/model` at the first slash; undefined when either part has not the shape of the catalogue ids */
export function parseCloudModel(value: string): { provider: string, model: string } | undefined {
  const slash = value.indexOf('/')
  if (slash < 0)
    return undefined
  const provider = value.slice(0, slash)
  const model = value.slice(slash + 1)
  return ASSISTANT_PROVIDER_ID_PATTERN.test(provider) && ASSISTANT_MODEL_ID_PATTERN.test(model) ? { provider, model } : undefined
}

/** The models of AI_MODELS that the engine serves on the runtime: what the Assistant can use self-hosted */
export function activatedModels(catalogue: ModelsCatalogue, engine: AiEngine, runtime: AiRuntime, models: string[]): ModelEntry[] {
  return modelEntries(catalogue, engine, runtime).filter(entry => models.includes(entry.id))
}

/**
 * What n8n needs to use a model of the catalogue: the name the engine serves it under and its OpenAI compatible
 * endpoint on n8n-starter-private (the ollama server for every model, one vllm container per model)
 */
export function selfHostedAssistant(entry: ModelEntry, engine: AiEngine): AssistantModel {
  return { model: entry.model, url: engine === 'ollama' ? OLLAMA_OPENAI_ENDPOINT : vllmEndpoint(entry.id) }
}

function sameUrl(a: string, b: string): boolean {
  return a.replace(/\/+$/, '') === b.replace(/\/+$/, '')
}

/** Whether a URL names a model server of this kit: the ollama server or a vllm container */
function isModelServer(url: string): boolean {
  let hostname: string
  try {
    hostname = new URL(url).hostname
  } catch {
    return false
  }
  return hostname === new URL(OLLAMA_ENDPOINT).hostname || hostname.startsWith(vllmContainerName(''))
}

/**
 * Classifies the model of compose/n8n/.env against the root .env: without a URL n8n calls a cloud provider, a URL
 * and name of an activated model is self-hosted, and a URL of a kit model server that fits no activated model is
 * stale (the engine or AI_MODELS changed since `config N8N_ASSISTANT` wrote it). Any other URL is an endpoint of
 * the user's own and is left alone.
 */
export function assistantTarget(catalogue: ModelsCatalogue, engine: AiEngine, runtime: AiRuntime, models: string[], { model, url }: AssistantEnv): AssistantTarget {
  if (url === undefined)
    return { kind: 'cloud' }
  const match = activatedModels(catalogue, engine, runtime, models).find((entry) => {
    const candidate = selfHostedAssistant(entry, engine)
    return candidate.model === model && sameUrl(candidate.url, url)
  })
  if (match !== undefined)
    return { kind: 'self-hosted', id: match.id }
  if (!isModelServer(url))
    return { kind: 'custom' }
  return { kind: 'stale', reason: `${ASSISTANT_MODEL_KEY}=${model ?? ''} at ${url} (${ASSISTANT_ENV_FILE}) is not a model of AI_MODELS served by ${engine} on ${runtime}` }
}

/** The model of the Assistant in compose/n8n/.env; empty while the file does not exist yet */
export async function readAssistantEnv(rootDir: string): Promise<AssistantEnv> {
  let content: string
  try {
    content = await readFile(join(rootDir, ASSISTANT_ENV_FILE), 'utf-8')
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT')
      throw error
    return {}
  }
  const env = parseEnvContent(content)
  return { model: env[ASSISTANT_MODEL_KEY] || undefined, url: env[ASSISTANT_MODEL_URL_KEY] || undefined }
}

/**
 * Writes the model and its URL into compose/n8n/.env, comments and other keys preserved; an empty URL clears the
 * endpoint of an earlier self-hosted model. Throws naming `setup` when the file does not exist.
 */
export async function writeAssistantModel(rootDir: string, { model, url }: AssistantModel): Promise<void> {
  const file = join(rootDir, ASSISTANT_ENV_FILE)
  let content: string
  try {
    content = await readFile(file, 'utf-8')
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT')
      throw error
    throw new Error(`No ${ASSISTANT_ENV_FILE} file found. Run ${runCommand('setup')} first.`)
  }
  await writeFile(file, updateEnvContent(content, { [ASSISTANT_MODEL_KEY]: model, [ASSISTANT_MODEL_URL_KEY]: url }))
}

/**
 * The warning of a root .env whose Assistant is on and points at a model the engine no longer serves, or undefined:
 * `config AI_ENGINE`, `config AI_RUNTIME` and `models select` report it, `tilt resources` refuses the plan
 */
export async function assistantStaleWarning(rootDir: string, current: Record<string, string>, catalogue: ModelsCatalogue): Promise<string | undefined> {
  if (current.N8N_ASSISTANT !== 'true')
    return undefined
  const { engine, runtime } = currentEngineRuntime(current)
  const target = assistantTarget(catalogue, engine, runtime, parseModelList(current.AI_MODELS ?? ''), await readAssistantEnv(rootDir))
  return target.kind === 'stale' ? `${target.reason}, run ${runCommand('config N8N_ASSISTANT')}` : undefined
}
