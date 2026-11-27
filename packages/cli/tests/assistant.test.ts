import type { ModelsCatalogue } from '../src/schemas/models'
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { afterEach, beforeEach, expect, test } from 'vitest'
import { ASSISTANT_MODEL_ID_PATTERN, ASSISTANT_PROVIDER_ID_PATTERN, assistantCatalogueSchema } from '../src/schemas/assistant'
import { activatedModels, ASSISTANT_CATALOGUE_FILE, ASSISTANT_ENV_FILE, ASSISTANT_MODEL_KEY, ASSISTANT_MODEL_URL_KEY, assistantStaleWarning, assistantTarget, cloudModel, cloudModels, OLLAMA_OPENAI_ENDPOINT, parseCloudModel, readAssistantCatalogue, readAssistantEnv, selfHostedAssistant, writeAssistantModel } from '../src/utils/assistant'
import { parseEnvContent, parseEnvDefaults } from '../src/utils/env'
import { modelEntries } from '../src/utils/models'

// a-1 on every runtime of both engines, b on gpu-nvidia only
const CATALOGUE: ModelsCatalogue = {
  models: [
    { id: 'a-1', label: 'A', ollama: { model: 'a:1b' }, vllm: { model: 'Org/A', args: '' } },
    { id: 'b', label: 'B', ollama: { model: 'b:70b', runtimes: ['gpu-nvidia'] }, vllm: { model: 'Org/B', args: '', runtimes: ['gpu-nvidia'] } },
  ],
}

const PROVIDERS = {
  providers: [
    { id: 'anthropic', label: 'Anthropic', models: [{ id: 'claude-x', label: 'Claude X' }, { id: 'claude-y', label: 'Claude Y', note: 'smaller' }] },
    { id: 'openrouter', label: 'OpenRouter', models: [{ id: 'vendor/model-z', label: 'Model Z' }] },
  ],
}

let rootDir: string

beforeEach(async () => {
  rootDir = await mkdtemp(join(tmpdir(), 'n8n-starter-assistant-'))
})

afterEach(async () => {
  await rm(rootDir, { recursive: true, force: true })
})

async function writeN8nEnv(content: string) {
  await mkdir(join(rootDir, 'compose', 'n8n'), { recursive: true })
  await writeFile(join(rootDir, ASSISTANT_ENV_FILE), content)
}

test('the cloud catalogue nests the models under their provider and refuses duplicates, empty lists and unknown keys', () => {
  expect(assistantCatalogueSchema.safeParse(PROVIDERS).success).toBe(true)
  expect(assistantCatalogueSchema.safeParse({ $schema: './models.cloud.schema.json', ...PROVIDERS }).success).toBe(true)

  const provider = PROVIDERS.providers[0]!
  const invalid = (providers: unknown) => assistantCatalogueSchema.safeParse({ providers }).error?.issues[0]?.message
  expect(invalid([])).toBe('the catalogue needs at least one provider')
  expect(invalid([provider, provider])).toBe('provider ids must be unique')
  expect(invalid([{ ...provider, models: [] }])).toBe('a provider needs at least one model')
  expect(invalid([{ ...provider, models: [provider.models[0], provider.models[0]] }])).toBe('model ids must be unique within a provider')
  // the same model id under two providers is two models
  expect(invalid([provider, { ...provider, id: 'other' }])).toBeUndefined()
  // a provider id is what n8n reads before the first slash, a model id may nest a vendor
  expect(invalid([{ ...provider, id: 'Anthropic' }])).toContain('Provider ids')
  expect(invalid([{ ...provider, id: 'open/router' }])).toContain('Provider ids')
  expect(invalid([{ ...provider, models: [{ id: 'has space', label: 'x' }] }])).toContain('Model ids')
  expect(invalid([{ ...provider, models: [{ id: '/leading', label: 'x' }] }])).toContain('Model ids')
  expect(invalid([{ ...provider, models: [{ id: 'x', label: '' }] }])).toBe('label must not be empty')
  expect(invalid([{ ...provider, url: 'https://example.com' }])).toBeDefined()
  expect(invalid([{ ...provider, models: [{ id: 'x', label: 'X', memory: 1 }] }])).toBeDefined()
})

test('a cloud model is the provider, a slash and the name of the model there', () => {
  expect(cloudModel('anthropic', 'claude-x')).toBe('anthropic/claude-x')
  // catalogue order, the first one being the default of the compose file
  expect(cloudModels(PROVIDERS)).toEqual(['anthropic/claude-x', 'anthropic/claude-y', 'openrouter/vendor/model-z'])

  // split at the first slash only: an aggregator names the vendor in the model
  expect(parseCloudModel('anthropic/claude-x')).toEqual({ provider: 'anthropic', model: 'claude-x' })
  expect(parseCloudModel('openrouter/vendor/model-z:free')).toEqual({ provider: 'openrouter', model: 'vendor/model-z:free' })
  for (const value of ['claude-x', 'a-1', '/claude-x', 'anthropic/', 'Anthropic/claude-x', 'anthropic/has space', 'anthropic//x'])
    expect(parseCloudModel(value), value).toBeUndefined()
})

test('a model of AI_MODELS is addressed by the name and the OpenAI endpoint of the engine that serves it', () => {
  const [ollama] = modelEntries(CATALOGUE, 'ollama', 'cpu-arm64')
  const [vllm] = modelEntries(CATALOGUE, 'vllm', 'cpu-arm64')

  // ollama: the one server, at the /v1 path of its OpenAI compatible API, the tag as the model name
  expect(OLLAMA_OPENAI_ENDPOINT).toBe('http://ollama:11434/v1')
  expect(selfHostedAssistant(ollama!, 'ollama')).toEqual({ model: 'a:1b', url: 'http://ollama:11434/v1' })
  // vllm: the container of the model, the Hugging Face id as the model name
  expect(selfHostedAssistant(vllm!, 'vllm')).toEqual({ model: 'Org/A', url: 'http://vllm-a-1:8000/v1' })

  // only what AI_MODELS lists and the engine serves on the runtime is a candidate
  expect(activatedModels(CATALOGUE, 'ollama', 'cpu-arm64', ['a-1', 'b', 'zzz']).map(entry => entry.id)).toEqual(['a-1'])
  expect(activatedModels(CATALOGUE, 'vllm', 'gpu-nvidia', ['b', 'a-1']).map(entry => entry.id)).toEqual(['a-1', 'b'])
  expect(activatedModels(CATALOGUE, 'ollama', 'cpu-arm64', [])).toEqual([])
})

test('the model of compose/n8n/.env is a cloud model, a model of AI_MODELS, an endpoint of your own or stale', () => {
  const target = (env: { model?: string, url?: string }, engine: 'ollama' | 'vllm' = 'ollama', models = ['a-1']) => assistantTarget(CATALOGUE, engine, 'cpu-arm64', models, env)

  // without a url n8n calls the provider named in the model, or its default
  expect(target({})).toEqual({ kind: 'cloud' })
  expect(target({ model: 'anthropic/claude-x' })).toEqual({ kind: 'cloud' })

  // name and endpoint of an activated model, a trailing slash aside
  expect(target({ model: 'a:1b', url: 'http://ollama:11434/v1' })).toEqual({ kind: 'self-hosted', id: 'a-1' })
  expect(target({ model: 'a:1b', url: 'http://ollama:11434/v1/' })).toEqual({ kind: 'self-hosted', id: 'a-1' })
  expect(target({ model: 'Org/A', url: 'http://vllm-a-1:8000/v1' }, 'vllm')).toEqual({ kind: 'self-hosted', id: 'a-1' })

  // any other host is the user's own endpoint, whatever the model is called
  expect(target({ model: 'a:1b', url: 'http://host.docker.internal:11434/v1' })).toEqual({ kind: 'custom' })
  expect(target({ model: 'gpt', url: 'https://api.example.com/v1' })).toEqual({ kind: 'custom' })
  expect(target({ model: 'x', url: 'not a url' })).toEqual({ kind: 'custom' })

  // a model server of the kit that fits no activated model: the engine changed, the model was deselected or renamed
  const stale = (env: { model?: string, url?: string }, engine: 'ollama' | 'vllm' = 'ollama', models = ['a-1']) => {
    const result = target(env, engine, models)
    return result.kind === 'stale' ? result.reason : result.kind
  }
  expect(stale({ model: 'Org/A', url: 'http://vllm-a-1:8000/v1' })).toBe('N8N_INSTANCE_AI_MODEL=Org/A at http://vllm-a-1:8000/v1 (compose/n8n/.env) is not a model of AI_MODELS served by ollama on cpu-arm64')
  expect(stale({ model: 'a:1b', url: 'http://ollama:11434/v1' }, 'vllm')).toContain('served by vllm on cpu-arm64')
  expect(stale({ model: 'a:1b', url: 'http://ollama:11434/v1' }, 'ollama', [])).toContain('is not a model of AI_MODELS')
  expect(stale({ model: 'b:70b', url: 'http://ollama:11434/v1' }, 'ollama', ['a-1', 'b'])).toContain('N8N_INSTANCE_AI_MODEL=b:70b')
  expect(stale({ model: 'Org/A', url: 'http://vllm-b:8000/v1' }, 'vllm')).toContain('at http://vllm-b:8000/v1')
  expect(stale({ url: 'http://ollama:11434/v1' })).toContain('N8N_INSTANCE_AI_MODEL= at http://ollama:11434/v1')
})

test('reads and writes the model of compose/n8n/.env, keeping comments and other keys', async () => {
  // no file yet: nothing held, and nothing to write to
  expect(await readAssistantEnv(rootDir)).toEqual({})
  await expect(writeAssistantModel(rootDir, { model: 'anthropic/claude-x', url: '' })).rejects.toThrow('No compose/n8n/.env file found. Run `pnpm run setup` first.')

  const template = '# required\nN8N_VERSION=1\n\n# optional\n# N8N_INSTANCE_AI_MODEL=anthropic/claude-x\n# N8N_INSTANCE_AI_MODEL_URL=\n'
  await writeN8nEnv(template)
  // a knob the template keeps commented out is not a value
  expect(await readAssistantEnv(rootDir)).toEqual({})

  await writeAssistantModel(rootDir, { model: 'a:1b', url: 'http://ollama:11434/v1' })
  expect(await readFile(join(rootDir, ASSISTANT_ENV_FILE), 'utf-8')).toBe(`${template}${ASSISTANT_MODEL_KEY}=a:1b\n${ASSISTANT_MODEL_URL_KEY}=http://ollama:11434/v1\n`)
  expect(await readAssistantEnv(rootDir)).toEqual({ model: 'a:1b', url: 'http://ollama:11434/v1' })

  // a cloud model clears the endpoint in place: an empty url reads as none
  await writeAssistantModel(rootDir, { model: 'anthropic/claude-x', url: '' })
  expect(await readFile(join(rootDir, ASSISTANT_ENV_FILE), 'utf-8')).toBe(`${template}${ASSISTANT_MODEL_KEY}=anthropic/claude-x\n${ASSISTANT_MODEL_URL_KEY}=\n`)
  expect(await readAssistantEnv(rootDir)).toEqual({ model: 'anthropic/claude-x' })
})

test('the stale warning names the command that fixes it and stays silent while the Assistant is off', async () => {
  await writeN8nEnv('N8N_INSTANCE_AI_MODEL=Org/A\nN8N_INSTANCE_AI_MODEL_URL=http://vllm-a-1:8000/v1\n')
  const root = { N8N_ASSISTANT: 'true', AI_ENGINE: 'ollama', AI_RUNTIME: 'cpu-arm64', AI_MODELS: 'a-1' }

  expect(await assistantStaleWarning(rootDir, root, CATALOGUE)).toBe('N8N_INSTANCE_AI_MODEL=Org/A at http://vllm-a-1:8000/v1 (compose/n8n/.env) is not a model of AI_MODELS served by ollama on cpu-arm64, run `pnpm run config N8N_ASSISTANT`')
  expect(await assistantStaleWarning(rootDir, { ...root, AI_ENGINE: 'vllm' }, CATALOGUE)).toBeUndefined()
  expect(await assistantStaleWarning(rootDir, { ...root, N8N_ASSISTANT: 'false' }, CATALOGUE)).toBeUndefined()
  // a root .env written before the key existed
  expect(await assistantStaleWarning(rootDir, { AI_ENGINE: 'ollama', AI_RUNTIME: 'cpu-arm64', AI_MODELS: 'a-1' }, CATALOGUE)).toBeUndefined()
})

test('readAssistantCatalogue fails naming the file when it is missing or invalid', async () => {
  await expect(readAssistantCatalogue(rootDir)).rejects.toThrow(`No cloud model catalogue found at ${join(rootDir, ASSISTANT_CATALOGUE_FILE)}`)

  await mkdir(join(rootDir, 'compose', 'models'), { recursive: true })
  await writeFile(join(rootDir, ASSISTANT_CATALOGUE_FILE), JSON.stringify({ providers: [] }))
  await expect(readAssistantCatalogue(rootDir)).rejects.toThrow(/Invalid cloud model catalogue .*models\.cloud\.json:[\s\S]*at least one provider/)

  await writeFile(join(rootDir, ASSISTANT_CATALOGUE_FILE), JSON.stringify(PROVIDERS))
  expect(await readAssistantCatalogue(rootDir)).toEqual(PROVIDERS)
})

test('the repository cloud catalogue is valid, mirrored by its editor schema, and its first model is the default of the n8n compose file', async () => {
  const repoRoot = fileURLToPath(new URL('../../../', import.meta.url))
  const catalogue = await readAssistantCatalogue(repoRoot)
  const models = cloudModels(catalogue)
  expect(models.length).toBeGreaterThan(0)
  // every entry is a value n8n accepts as provider/model
  for (const model of models)
    expect(parseCloudModel(model), model).toBeDefined()

  // the editor schema carries the same shape and patterns as the zod schema
  const raw = JSON.parse(await readFile(join(repoRoot, ASSISTANT_CATALOGUE_FILE), 'utf-8'))
  expect(raw.$schema).toBe('./models.cloud.schema.json')
  const schema = JSON.parse(await readFile(join(repoRoot, 'compose/models/models.cloud.schema.json'), 'utf-8'))
  expect(schema.properties.providers).toMatchObject({ type: 'array', minItems: 1, items: { $ref: '#/$defs/provider' } })
  expect(schema.additionalProperties).toBe(false)
  expect(schema.$defs.provider.properties.id.pattern).toBe(ASSISTANT_PROVIDER_ID_PATTERN.source)
  expect(schema.$defs.provider.properties.models).toMatchObject({ type: 'array', minItems: 1, items: { $ref: '#/$defs/model' } })
  expect(schema.$defs.provider.required).toEqual(['id', 'label', 'models'])
  expect(schema.$defs.provider.additionalProperties).toBe(false)
  expect(schema.$defs.model.properties.id.pattern).toBe(ASSISTANT_MODEL_ID_PATTERN.source)
  expect(Object.keys(schema.$defs.model.properties)).toEqual(['id', 'label', 'note'])
  expect(schema.$defs.model.required).toEqual(['id', 'label'])
  expect(schema.$defs.model.additionalProperties).toBe(false)

  // n8n takes an empty N8N_INSTANCE_AI_MODEL literally, so the compose file carries a default: the first model of the
  // catalogue, shown commented out in the template like every knob (see ../../../SPEC.md)
  const compose = await readFile(join(repoRoot, 'compose/n8n/docker-compose.yml'), 'utf-8')
  expect(compose).toContain(`${ASSISTANT_MODEL_KEY}: \${${ASSISTANT_MODEL_KEY}:-${models[0]}}`)
  expect(compose).toContain(`${ASSISTANT_MODEL_URL_KEY}: \${${ASSISTANT_MODEL_URL_KEY}:-}`)
  const template = await readFile(join(repoRoot, 'compose/n8n/.env.template'), 'utf-8')
  expect(parseEnvDefaults(template)[ASSISTANT_MODEL_KEY]).toBe(models[0])
  expect(parseEnvDefaults(template)[ASSISTANT_MODEL_URL_KEY]).toBe('')
  // neither key is live in the template: `config N8N_ASSISTANT` writes them into the .env
  expect(parseEnvContent(template)[ASSISTANT_MODEL_KEY]).toBeUndefined()

  // n8n runs without the Assistant: nothing of its anchor is required
  const anchor = compose.slice(compose.indexOf('x-n8n-env-assistant:'), compose.indexOf('x-n8n-env-hosting:'))
  expect(anchor).toContain('N8N_INSTANCE_AI_ENABLED: ${N8N_ASSISTANT:-false}')
  expect(anchor).not.toContain(':?}')
})
