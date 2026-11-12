import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { stripVTControlCharacters } from 'node:util'
import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import type { DockerRunner } from '../src/utils/docker'
import { parseEnvContent } from '../src/utils/env'
import { setLogLevel } from '../src/utils/logger'
import { DOCKER_INFO_FORMAT } from '../src/utils/platform'

const { multiselectMock, introMock, outroMock, logInfoMock, logErrorMock, CANCEL } = vi.hoisted(() => ({
  multiselectMock: vi.fn(),
  introMock: vi.fn(),
  outroMock: vi.fn(),
  logInfoMock: vi.fn(),
  logErrorMock: vi.fn(),
  CANCEL: Symbol('clack-cancel'),
}))

vi.mock('@clack/prompts', () => ({
  intro: introMock,
  outro: outroMock,
  cancel: vi.fn(),
  text: vi.fn(),
  select: vi.fn(),
  multiselect: multiselectMock,
  isCancel: (value: unknown) => value === CANCEL,
  log: { info: logInfoMock, warn: vi.fn(), success: vi.fn(), error: logErrorMock, step: vi.fn(), message: vi.fn() },
}))

const { models, validateModels } = await import('../src/commands/models')

const ENV_CONTENT = `# The domain to run the docker compose services
DOMAIN=n8n.localhost
N8N_VARIANT=dev
AI_RUNTIME=cpu-arm64
AI_ENGINE=vllm
# The models of ./compose/models/models.json that start with the stack, comma separated ids
AI_MODELS=
`

// ollama: a on gpu-nvidia only; vllm: a-1 everywhere and b on gpu-nvidia only
const CATALOGUE = {
  models: [
    { id: 'a', label: 'A', ollama: { model: 'a:1b', runtimes: ['gpu-nvidia'] } },
    { id: 'a-1', label: 'A', vllm: { model: 'Org/A', args: '--max-model-len=4096' } },
    { id: 'b', label: 'B', vllm: { model: 'Org/B', args: '', runtimes: ['gpu-nvidia'] } },
  ],
}

let rootDir: string
let logSpy: ReturnType<typeof vi.spyOn>

beforeEach(async () => {
  rootDir = await mkdtemp(join(tmpdir(), 'n8n-starter-models-command-'))
  multiselectMock.mockReset()
  introMock.mockReset()
  outroMock.mockReset()
  logInfoMock.mockReset()
  logErrorMock.mockReset()
  logSpy = vi.spyOn(console, 'log').mockImplementation(() => {})
})

afterEach(async () => {
  logSpy.mockRestore()
  await rm(rootDir, { recursive: true, force: true })
  process.exitCode = 0
  setLogLevel('info')
})

async function writeCatalogue(catalogue: unknown = CATALOGUE) {
  const dir = join(rootDir, 'compose', 'models')
  await mkdir(dir, { recursive: true })
  await writeFile(join(dir, 'models.json'), JSON.stringify(catalogue))
}

async function writeEnv(content = ENV_CONTENT) {
  const envPath = join(rootDir, '.env')
  await writeFile(envPath, content)
  return envPath
}

const ARM_LINE = 'aarch64|17179869184|8|Docker Desktop|io.containerd.runc.v2,runc,\n'
/** The daemon line of `docker info`, every other call is unexpected; fixed host values keep the detection stable */
function platform(info = ARM_LINE) {
  const calls: string[][] = []
  const run: DockerRunner = async (args) => {
    calls.push(args)
    if (args[0] === 'info' && args[2] === DOCKER_INFO_FORMAT)
      return info
    throw new Error(`Unexpected docker call: ${args.join(' ')}`)
  }
  return { options: { run, arch: 'arm64', os: 'linux' as const, totalmem: 32 * 1024 ** 3, exists: async () => false }, calls }
}

test('models read prints one block per engine and model and nothing else', async () => {
  await writeCatalogue()
  setLogLevel('error')

  await models(rootDir, ['read'])

  expect(logSpy).toHaveBeenCalledOnce()
  expect(stripVTControlCharacters(logSpy.mock.calls[0]![0] as string)).toBe([
    'ollama/a',
    'model=a:1b',
    'label=A',
    'runtimes=gpu-nvidia',
    '',
    'vllm/a-1',
    'model=Org/A',
    'label=A',
    'args=--max-model-len=4096',
    '',
    'vllm/b',
    'model=Org/B',
    'label=B',
    'args=',
    'runtimes=gpu-nvidia',
  ].join('\n'))
  expect(introMock).not.toHaveBeenCalled()
  expect(outroMock).not.toHaveBeenCalled()
  expect(process.exitCode).not.toBe(1)
})

test('models read filters by a part of an engine or id and prints the records as JSON with --json', async () => {
  await writeCatalogue()

  await models(rootDir, ['read', 'ollama'])
  await models(rootDir, ['read', 'B'], { json: true })

  expect(stripVTControlCharacters(logSpy.mock.calls[0]![0] as string)).toBe('ollama/a\nmodel=a:1b\nlabel=A\nruntimes=gpu-nvidia')
  expect(JSON.parse(logSpy.mock.calls[1]![0] as string)).toEqual([
    { engine: 'vllm', id: 'b', model: 'Org/B', label: 'B', args: '', runtimes: ['gpu-nvidia'] },
  ])
})

test('models read highlights the keys in cyan when colours are on', async () => {
  await writeCatalogue()
  const previous = { FORCE_COLOR: process.env.FORCE_COLOR, NO_COLOR: process.env.NO_COLOR }
  try {
    // FORCE_COLOR wins over NO_COLOR and the missing tty, see util.styleText
    process.env.FORCE_COLOR = '1'
    delete process.env.NO_COLOR
    await models(rootDir, ['read', 'a-1'])
    expect(logSpy.mock.calls[0]![0]).toBe('vllm/a-1\n\u001B[36mmodel\u001B[39m=Org/A\n\u001B[36mlabel\u001B[39m=A\n\u001B[36margs\u001B[39m=--max-model-len=4096')
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined)
        delete process.env[key]
      else
        process.env[key] = value
    }
  }
})

test('models read fails naming the file when the catalogue is missing or invalid, and the filter when nothing matches', async () => {
  await models(rootDir, ['read'])
  expect(logErrorMock).toHaveBeenCalledWith(expect.stringContaining('No model catalogue found'))
  expect(process.exitCode).toBe(1)

  process.exitCode = 0
  // memory is a number of GB
  await writeCatalogue({ models: [{ id: 'a', label: 'A', ollama: { model: 'a', memory: '2 GB' } }] })
  await models(rootDir, ['read'])
  expect(logErrorMock).toHaveBeenCalledWith(expect.stringMatching(/Invalid model catalogue .*models\.json/))
  expect(process.exitCode).toBe(1)

  process.exitCode = 0
  await writeCatalogue()
  await models(rootDir, ['read', 'nope'], { json: true })
  expect(logErrorMock).toHaveBeenCalledWith('No model matches "nope", run `pnpm run models read` for the list')
  expect(logSpy).not.toHaveBeenCalled()
  expect(process.exitCode).toBe(1)
})

test('models select lists the models of the current engine, writes the selection and prints the endpoints', async () => {
  const envPath = await writeEnv()
  await writeCatalogue()
  multiselectMock.mockResolvedValue(['a-1'])

  await models(rootDir, ['select'], {}, platform().options)

  // every entry is listed, the one the runtime cannot run is disabled
  expect(multiselectMock).toHaveBeenCalledWith(expect.objectContaining({
    options: [
      expect.objectContaining({ value: 'a-1', hint: 'A, Org/A', disabled: false }),
      expect.objectContaining({ value: 'b', hint: expect.stringContaining('not on cpu-arm64'), disabled: true }),
    ],
    initialValues: [],
    required: false,
  }))
  // the docker memory the estimates compare with
  expect(logInfoMock).toHaveBeenCalledWith('Detected docker aarch64, 8 cpus, 16 GB memory (Docker Desktop), host linux/arm64 32 GB, no gpu')
  // the endpoint n8n uses, named after the id of the entry
  expect(logInfoMock).toHaveBeenCalledWith(expect.stringContaining('a-1 runs at http://vllm-a-1:8000/v1'))
  // no gateway is set, so none is mentioned
  expect(logInfoMock).not.toHaveBeenCalledWith(expect.stringContaining('litellm'))
  const updated = await readFile(envPath, 'utf-8')
  expect(parseEnvContent(updated).AI_MODELS).toBe('a-1')
  // comments and other keys are preserved
  expect(updated).toContain('# The models of ./compose/models/models.json')
  expect(parseEnvContent(updated).AI_ENGINE).toBe('vllm')
  expect(process.exitCode).toBe(0)
})

test('models select names the endpoint of the gateway when AI_GATEWAY is set', async () => {
  await writeEnv(`${ENV_CONTENT}AI_GATEWAY=litellm\n`)
  await writeCatalogue()

  await models(rootDir, ['select', 'a-1'], {}, platform().options)

  expect(logInfoMock).toHaveBeenCalledWith(expect.stringContaining('a-1 runs at http://vllm-a-1:8000/v1'))
  expect(logInfoMock).toHaveBeenCalledWith('litellm serves every model of AI_MODELS under its id at http://litellm:4000/v1, bearer token LITELLM_MASTER_KEY of compose/models/litellm/.env')
})

test('models select preselects the current ids that the runtime can run', async () => {
  await writeEnv(ENV_CONTENT.replace('AI_MODELS=', 'AI_MODELS=a-1,b,zzz'))
  await writeCatalogue()
  multiselectMock.mockResolvedValue(['a-1'])

  await models(rootDir, ['select'], {}, platform().options)

  expect(multiselectMock).toHaveBeenCalledWith(expect.objectContaining({ initialValues: ['a-1'] }))
})

test('models select skips the prompt when no model of the engine runs on the runtime', async () => {
  const envPath = await writeEnv(ENV_CONTENT.replace('AI_ENGINE=vllm', 'AI_ENGINE=ollama').replace('AI_MODELS=', 'AI_MODELS=a'))
  await writeCatalogue()

  await models(rootDir, ['select'], {}, platform().options)

  expect(multiselectMock).not.toHaveBeenCalled()
  expect(logInfoMock).toHaveBeenCalledWith(expect.stringContaining('No model of ollama runs on cpu-arm64'))
  expect(parseEnvContent(await readFile(envPath, 'utf-8')).AI_MODELS).toBe('')
})

test('models select ids writes without a prompt and "" clears the list', async () => {
  const envPath = await writeEnv(ENV_CONTENT.replace('AI_ENGINE=vllm', 'AI_ENGINE=ollama').replace('AI_RUNTIME=cpu-arm64', 'AI_RUNTIME=gpu-nvidia'))
  await writeCatalogue()
  const { options, calls } = platform()

  await models(rootDir, ['select', 'a'], {}, options)
  expect(multiselectMock).not.toHaveBeenCalled()
  // ids on the command line never ask docker
  expect(calls).toEqual([])
  expect(parseEnvContent(await readFile(envPath, 'utf-8')).AI_MODELS).toBe('a')
  expect(logInfoMock).toHaveBeenCalledWith(expect.stringContaining('http://ollama:11434'))

  await models(rootDir, ['select', ''])
  expect(parseEnvContent(await readFile(envPath, 'utf-8')).AI_MODELS).toBe('')
  expect(process.exitCode).toBe(0)
})

test('models select logs its intro unless the caller owns it, as config AI_MODELS does', async () => {
  const envPath = await writeEnv()
  await writeCatalogue()

  await models(rootDir, ['select', 'a-1'])
  expect(introMock.mock.calls).toEqual([['n8n-starter models select']])

  introMock.mockReset()
  await models(rootDir, ['select', ''], { intro: false })
  expect(introMock).not.toHaveBeenCalled()
  // the outro still closes the run
  expect(outroMock).toHaveBeenCalledTimes(2)
  expect(parseEnvContent(await readFile(envPath, 'utf-8')).AI_MODELS).toBe('')
})

test.each([
  ['Qwen/Qwen3.5-0.8B', 'comma separated lowercase ids'],
  // b exists for vllm but not on cpu-arm64, zzz is not in the catalogue
  ['a-1,b', 'b: not served by vllm on cpu-arm64'],
  ['zzz', 'zzz: not served by vllm on cpu-arm64'],
])('models select %j fails without writing or prompting', async (value, message) => {
  const envPath = await writeEnv()
  await writeCatalogue()

  await models(rootDir, ['select', value])

  expect(logErrorMock).toHaveBeenCalledWith(expect.stringContaining(message))
  expect(multiselectMock).not.toHaveBeenCalled()
  expect(await readFile(envPath, 'utf-8')).toBe(ENV_CONTENT)
  expect(process.exitCode).toBe(1)
})

test('validateModels returns the reason a value is rejected', () => {
  const current = parseEnvContent(ENV_CONTENT)

  expect(validateModels(CATALOGUE as never, current, 'a-1')).toBeUndefined()
  expect(validateModels(CATALOGUE as never, current, '')).toBeUndefined()
  expect(validateModels(CATALOGUE as never, current, 'a-1,b')).toContain('b: not served by vllm on cpu-arm64')
  expect(validateModels(CATALOGUE as never, { ...current, AI_RUNTIME: 'gpu-nvidia' }, 'a-1,b')).toBeUndefined()
})

test('models select leaves the .env file untouched when the prompt is cancelled', async () => {
  const envPath = await writeEnv()
  await writeCatalogue()
  multiselectMock.mockResolvedValue(CANCEL)

  await models(rootDir, ['select'], {}, platform().options)

  expect(await readFile(envPath, 'utf-8')).toBe(ENV_CONTENT)
})

test('models select fails without writing when the catalogue or the .env file is missing', async () => {
  const envPath = await writeEnv()
  await models(rootDir, ['select'])
  expect(logErrorMock).toHaveBeenCalledWith(expect.stringContaining('No model catalogue found'))
  expect(await readFile(envPath, 'utf-8')).toBe(ENV_CONTENT)
  expect(process.exitCode).toBe(1)

  process.exitCode = 0
  await rm(envPath)
  await writeCatalogue()
  await models(rootDir, ['select'], {}, platform().options)
  expect(logErrorMock).toHaveBeenCalledWith(expect.stringContaining('No .env file found'))
  expect(multiselectMock).not.toHaveBeenCalled()
  expect(process.exitCode).toBe(1)
})

test.each([
  [[], 'Missing sub-command for models'],
  [['nope'], 'Unknown sub-command "nope" for models'],
])('models %j fails listing the sub-commands', async (rest, message) => {
  await models(rootDir, rest)

  expect(logErrorMock).toHaveBeenCalledWith(expect.stringContaining(message))
  expect(logErrorMock).toHaveBeenCalledWith(expect.stringContaining('read, select'))
  expect(process.exitCode).toBe(1)
})

test('models select points out an estimate above the docker memory without disabling the entry', async () => {
  await writeEnv(ENV_CONTENT.replace('AI_ENGINE=vllm', 'AI_ENGINE=ollama'))
  await writeCatalogue({ models: [
    { id: 'small', label: 'Small', ollama: { model: 'small:1b', memory: 6 } },
    { id: 'big', label: 'Big', ollama: { model: 'big:70b', memory: 40, note: 'needs a big machine' } },
  ] })
  multiselectMock.mockResolvedValue(['big'])

  await models(rootDir, ['select'], {}, platform().options)

  const options = multiselectMock.mock.calls[0]![0].options as { value: string, hint: string, disabled: boolean }[]
  expect(options.map(option => ({ ...option, hint: stripVTControlCharacters(option.hint) }))).toEqual([
    { value: 'small', label: 'small', hint: 'Small, small:1b, ~6 GB RAM', disabled: false },
    { value: 'big', label: 'big', hint: 'Big, big:70b, ~40 GB RAM, over the 16 GB of docker memory, needs a big machine', disabled: false },
  ])
})
