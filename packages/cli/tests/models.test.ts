import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { stripVTControlCharacters } from 'node:util'
import { afterEach, beforeEach, expect, test } from 'vitest'
import { AI_RUNTIMES } from '../src/schemas/config'
import { MODEL_ID_MAX_LENGTH, MODEL_ID_PATTERN, modelsCatalogueSchema } from '../src/schemas/models'
import { currentEngineRuntime, engineEntries, formatMemory, formatModelList, listModels, modelEntries, modelOptions, modelsCatalogueFile, parseModelList, readModelsCatalogue, unsupportedModels, vllmContainerName, vllmEndpoint } from '../src/utils/models'

// a served by both engines, b-1 by ollama on gpu-nvidia only
const CATALOGUE = {
  models: [
    { id: 'a', label: 'A 1B', ollama: { model: 'a:1b', memory: 2 }, vllm: { model: 'Org/A-1B', args: '--max-model-len=4096' } },
    { id: 'b-1', label: 'B 70B', ollama: { model: 'b:70b', memory: 40, note: 'needs a big card', runtimes: ['gpu-nvidia'] } },
  ],
}

async function writeCatalogue(rootDir: string, catalogue: unknown) {
  const dir = join(rootDir, 'compose', 'models')
  await mkdir(dir, { recursive: true })
  await writeFile(join(dir, 'models.json'), JSON.stringify(catalogue))
}

let rootDir: string

beforeEach(async () => {
  rootDir = await mkdtemp(join(tmpdir(), 'n8n-starter-models-'))
  await writeCatalogue(rootDir, CATALOGUE)
})

afterEach(async () => {
  await rm(rootDir, { recursive: true, force: true })
})

test('readModelsCatalogue validates compose/models/models.json', async () => {
  const catalogue = await readModelsCatalogue(rootDir)

  expect(catalogue.models.map(model => model.id)).toEqual(['a', 'b-1'])
  expect(catalogue.models[0]!.vllm!.args).toBe('--max-model-len=4096')
})

test('readModelsCatalogue names the file when it is missing or invalid', async () => {
  await expect(readModelsCatalogue(join(rootDir, 'nowhere'))).rejects.toThrow('No model catalogue found at')

  // a vllm block needs args
  await writeCatalogue(rootDir, { models: [{ id: 'a', label: 'A', vllm: { model: 'Org/A' } }] })
  await expect(readModelsCatalogue(rootDir)).rejects.toThrow(/Invalid model catalogue .*models\.json/)
})

test('catalogue schema rejects bad ids, memory and notes, unknown fields, unknown runtimes, duplicate ids and models without an engine', () => {
  const valid = (catalogue: unknown) => modelsCatalogueSchema.safeParse(catalogue).success
  const one = (model: Record<string, unknown>) => valid({ models: [{ label: 'A', ollama: { model: 'a' }, ...model }] })

  expect(valid(CATALOGUE)).toBe(true)
  // an id is a DNS label: no slashes, dots or uppercase, no leading or trailing dash, at most 58 characters
  expect(one({ id: 'Org/A' })).toBe(false)
  expect(one({ id: 'a.1' })).toBe(false)
  expect(one({ id: 'A' })).toBe(false)
  expect(one({ id: 'a-' })).toBe(false)
  expect(one({ id: 'a'.repeat(MODEL_ID_MAX_LENGTH) })).toBe(true)
  expect(one({ id: 'a'.repeat(MODEL_ID_MAX_LENGTH + 1) })).toBe(false)
  // memory is a number of GB, the unit is added when it is shown; a note is a non-empty string
  expect(one({ id: 'a', ollama: { model: 'a', memory: '2 GB' } })).toBe(false)
  expect(one({ id: 'a', ollama: { model: 'a', memory: 0 } })).toBe(false)
  expect(one({ id: 'a', ollama: { model: 'a', note: '' } })).toBe(false)
  // no unknown field on the model or in a block, params is gone
  expect(one({ id: 'a', extra: 1 })).toBe(false)
  expect(one({ id: 'a', params: '1B' })).toBe(false)
  expect(one({ id: 'a', ollama: { model: 'a', params: '1B' } })).toBe(false)
  expect(one({ id: 'a', ollama: { model: 'a', runtimes: ['gpu-intel'] } })).toBe(false)
  // a model needs at least one engine block, ids are unique
  expect(valid({ models: [{ id: 'a', label: 'A' }] })).toBe(false)
  expect(valid({ models: [{ id: 'a', label: 'A', vllm: { model: 'Org/A', args: '' } }] })).toBe(true)
  expect(valid({ models: [{ id: 'a', label: 'A', ollama: { model: 'a' } }, { id: 'a', label: 'B', ollama: { model: 'b' } }] })).toBe(false)
})

test('engineEntries flattens the models an engine serves, in catalogue order', async () => {
  const catalogue = await readModelsCatalogue(rootDir)

  expect(engineEntries(catalogue, 'ollama')).toEqual([
    { id: 'a', label: 'A 1B', model: 'a:1b', memory: 2 },
    { id: 'b-1', label: 'B 70B', model: 'b:70b', memory: 40, note: 'needs a big card', runtimes: ['gpu-nvidia'] },
  ])
  expect(engineEntries(catalogue, 'vllm')).toEqual([{ id: 'a', label: 'A 1B', model: 'Org/A-1B', args: '--max-model-len=4096' }])
})

test('modelEntries keeps the entries of the engine that run on the runtime', async () => {
  const catalogue = await readModelsCatalogue(rootDir)

  expect(modelEntries(catalogue, 'ollama', 'cpu-arm64').map(entry => entry.id)).toEqual(['a'])
  expect(modelEntries(catalogue, 'ollama', 'gpu-nvidia').map(entry => entry.id)).toEqual(['a', 'b-1'])
  expect(modelEntries(catalogue, 'vllm', 'gpu-amd').map(entry => entry.id)).toEqual(['a'])
})

test('listModels prints one record per engine and model, engine and id first, filtered by a part of either', async () => {
  const catalogue = await readModelsCatalogue(rootDir)

  const all = listModels(catalogue)
  expect(all).toEqual([
    { engine: 'ollama', id: 'a', model: 'a:1b', label: 'A 1B', memory: 2 },
    { engine: 'ollama', id: 'b-1', model: 'b:70b', label: 'B 70B', memory: 40, note: 'needs a big card', runtimes: ['gpu-nvidia'] },
    { engine: 'vllm', id: 'a', model: 'Org/A-1B', label: 'A 1B', args: '--max-model-len=4096' },
  ])
  // the key order is the printed order
  expect(Object.keys(all[2]!)).toEqual(['engine', 'id', 'model', 'label', 'args'])
  expect(listModels(catalogue, 'vllm').map(record => `${record.engine}/${record.id}`)).toEqual(['vllm/a'])
  expect(listModels(catalogue, 'B-1').map(record => `${record.engine}/${record.id}`)).toEqual(['ollama/b-1'])
  expect(listModels(catalogue, 'Org')).toEqual([])
  expect(listModels(catalogue, 'zzz')).toEqual([])
})

test('modelOptions lists every entry with its memory in the unit of the runtime, disabled when the runtime cannot run it', async () => {
  const catalogue = await readModelsCatalogue(rootDir)

  expect(modelOptions(catalogue, 'ollama', 'gpu-nvidia')).toEqual([
    { value: 'a', label: 'a', hint: 'A 1B, a:1b, ~2 GB VRAM', disabled: false },
    { value: 'b-1', label: 'b-1', hint: 'B 70B, b:70b, ~40 GB VRAM, needs a big card', disabled: false },
  ])
  // the reason is colored on a tty, the text stays the same
  const [supported, unsupported] = modelOptions(catalogue, 'ollama', 'cpu-arm64')
  expect(supported.hint).toBe('A 1B, a:1b, ~2 GB RAM')
  expect(unsupported).toMatchObject({ value: 'b-1', label: 'b-1', disabled: true })
  expect(stripVTControlCharacters(unsupported.hint ?? '')).toBe('B 70B, b:70b, ~40 GB RAM, needs a big card, not on cpu-arm64')
  // an engine lists only the models it serves
  expect(modelOptions(catalogue, 'vllm', 'cpu-arm64').map(option => option.value)).toEqual(['a'])
})

test('modelOptions points out an estimate above the docker memory on the cpu runtimes only, without disabling it', async () => {
  const catalogue = await readModelsCatalogue(rootDir)

  const [small, big] = modelOptions(catalogue, 'ollama', 'cpu-x86-64', { memory: 16 })
  expect(small).toEqual({ value: 'a', label: 'a', hint: 'A 1B, a:1b, ~2 GB RAM', disabled: false })
  expect(big!.disabled).toBe(true)
  expect(stripVTControlCharacters(big!.hint ?? '')).toBe('B 70B, b:70b, ~40 GB RAM, over the 16 GB of docker memory, needs a big card, not on cpu-x86-64')
  // the VRAM of a gpu is unknown, so no comparison there; an entry without an estimate is never pointed out
  expect(modelOptions(catalogue, 'ollama', 'gpu-nvidia', { memory: 16 })[1]!.hint).toBe('B 70B, b:70b, ~40 GB VRAM, needs a big card')
  expect(modelOptions(catalogue, 'vllm', 'cpu-arm64', { memory: 1 })[0]!.hint).toBe('A 1B, Org/A-1B')
  // equal is within the memory
  expect(modelOptions(catalogue, 'ollama', 'cpu-arm64', { memory: 2 })[0]!.hint).toBe('A 1B, a:1b, ~2 GB RAM')
})

test('formatMemory marks the estimate and names RAM or VRAM after the runtime', () => {
  expect(formatMemory(1.5, 'cpu-arm64')).toBe('~1.5 GB RAM')
  expect(formatMemory(6, 'cpu-x86-64')).toBe('~6 GB RAM')
  expect(formatMemory(16, 'gpu-nvidia')).toBe('~16 GB VRAM')
  expect(formatMemory(16, 'gpu-amd')).toBe('~16 GB VRAM')
})

test('AI_MODELS round-trips as a comma separated list', () => {
  expect(parseModelList('')).toEqual([])
  expect(parseModelList('a')).toEqual(['a'])
  expect(parseModelList(' a, b ,')).toEqual(['a', 'b'])
  expect(formatModelList(['a', 'b'])).toBe('a,b')
  expect(formatModelList([])).toBe('')
})

test('the vllm docker name and endpoint come from the catalogue id', () => {
  expect(vllmContainerName('qwen3-5-4b')).toBe('vllm-qwen3-5-4b')
  expect(vllmEndpoint('qwen3-5-0-8b')).toBe('http://vllm-qwen3-5-0-8b:8000/v1')
})

test('currentEngineRuntime falls back to the defaults and unsupportedModels names the ids the engine does not serve', async () => {
  const catalogue = await readModelsCatalogue(rootDir)

  expect(currentEngineRuntime({})).toEqual({ engine: 'ollama', runtime: 'cpu-arm64' })
  expect(currentEngineRuntime({ AI_ENGINE: 'vllm', AI_RUNTIME: 'gpu-amd' })).toEqual({ engine: 'vllm', runtime: 'gpu-amd' })
  expect(currentEngineRuntime({ AI_ENGINE: 'llamacpp', AI_RUNTIME: 'gpu-intel' })).toEqual({ engine: 'ollama', runtime: 'cpu-arm64' })
  expect(unsupportedModels(catalogue, 'ollama', 'cpu-arm64', ['a', 'b-1', 'zzz'])).toEqual(['b-1', 'zzz'])
  expect(unsupportedModels(catalogue, 'ollama', 'gpu-nvidia', ['a', 'b-1'])).toEqual([])
  expect(unsupportedModels(catalogue, 'vllm', 'gpu-nvidia', ['a', 'b-1'])).toEqual(['b-1'])
})

test('modelsCatalogueFile points at compose/models/models.json', () => {
  expect(modelsCatalogueFile(rootDir)).toBe(join(rootDir, 'compose', 'models', 'models.json'))
})

test('the repository catalogue is valid, serves every model on both engines and matches the editor schema', async () => {
  const repoRoot = fileURLToPath(new URL('../../../', import.meta.url))
  const catalogue = await readModelsCatalogue(repoRoot)

  const ids = ['qwen3-5-0-8b', 'qwen3-5-2b', 'qwen3-5-4b']
  expect(catalogue.models.map(model => model.id)).toEqual(ids)
  // every model has both engine blocks, each with its memory estimate
  for (const model of catalogue.models) {
    expect(model.ollama?.memory, `${model.id} ollama`).toBeGreaterThan(0)
    expect(model.vllm?.memory, `${model.id} vllm`).toBeGreaterThan(0)
  }
  // every model runs on every runtime of both engines, the memory estimate is the only guard
  for (const runtime of AI_RUNTIMES) {
    expect(modelEntries(catalogue, 'ollama', runtime).map(entry => entry.id)).toEqual(ids)
    expect(modelEntries(catalogue, 'vllm', runtime).map(entry => entry.id)).toEqual(ids)
  }

  // the editor schema enforces the same ids, blocks, memory and runtimes as the zod schema
  const schema = JSON.parse(await readFile(join(repoRoot, 'compose', 'models', 'models.schema.json'), 'utf-8'))
  expect(schema.required).toEqual(['models'])
  expect(schema.$defs.model.properties.id.pattern).toBe(MODEL_ID_PATTERN.source)
  expect(schema.$defs.model.properties.id.maxLength).toBe(MODEL_ID_MAX_LENGTH)
  expect(schema.$defs.model.required).toEqual(['id', 'label'])
  expect(schema.$defs.model.anyOf).toEqual([{ required: ['ollama'] }, { required: ['vllm'] }])
  expect(schema.$defs.model.properties).not.toHaveProperty('params')
  expect(schema.$defs.serving.properties.memory).toMatchObject({ type: 'number', exclusiveMinimum: 0 })
  expect(schema.$defs.serving.properties.note.type).toBe('string')
  expect(schema.$defs.serving.properties.runtimes.items.enum).toEqual([...AI_RUNTIMES])
  expect(schema.$defs.ollama.required).toEqual(['model'])
  expect(schema.$defs.vllm.required).toEqual(['model', 'args'])
})
