import { existsSync } from 'node:fs'
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { stripVTControlCharacters } from 'node:util'
import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import { AI_ENGINES, AI_GATEWAYS, AI_RUNTIMES, aiGatewaySchema, configSchema, domainSchema, N8N_VARIANTS } from '../src/schemas/config'
import type { DockerRunner } from '../src/utils/docker'
import { parseEnvContent, updateEnvContent } from '../src/utils/env'
import { setLogLevel } from '../src/utils/logger'
import { DOCKER_INFO_FORMAT } from '../src/utils/platform'

const { introMock, textMock, selectMock, multiselectMock, logInfoMock, logWarnMock, logErrorMock, CANCEL } = vi.hoisted(() => ({
  introMock: vi.fn(),
  textMock: vi.fn(),
  selectMock: vi.fn(),
  multiselectMock: vi.fn(),
  logInfoMock: vi.fn(),
  logWarnMock: vi.fn(),
  logErrorMock: vi.fn(),
  CANCEL: Symbol('clack-cancel'),
}))

vi.mock('@clack/prompts', () => ({
  intro: introMock,
  outro: vi.fn(),
  cancel: vi.fn(),
  text: textMock,
  select: selectMock,
  multiselect: multiselectMock,
  isCancel: (value: unknown) => value === CANCEL,
  log: { info: logInfoMock, warn: logWarnMock, success: vi.fn(), error: logErrorMock, step: vi.fn(), message: vi.fn() },
}))

const { config, CONFIG_KEYS, CONFIG_KEY_DESCRIPTIONS } = await import('../src/commands/config')

const ENV_CONTENT = `# Which variant of n8n to run in ./compose/n8n
# Options: dev, build, community or enterprise
N8N_VARIANT=dev
# The hardware supported ai runtime
# Options: cpu-arm64, cpu-x86-64, gpu-nvidia or gpu-amd
AI_RUNTIME=cpu-arm64
# The engine serving the AI models in ./compose/models
# Options: ollama or vllm
AI_ENGINE=ollama
# The gateway in front of the AI models in ./compose/models
# Options: empty for none, or litellm
AI_GATEWAY=
# The models of ./compose/models/models.json that start with the stack, comma separated ids
AI_MODELS=
# The domain to run the docker compose services
DOMAIN=n8n.localhost
`

const VALID_CONFIG = {
  DOMAIN: 'n8n.localhost',
  AI_RUNTIME: 'cpu-arm64',
  AI_ENGINE: 'ollama',
  AI_MODELS: 'qwen3-5-0-8b,qwen3-5-4b',
  N8N_VARIANT: 'dev',
}

// ollama only on gpu-nvidia; vllm one model everywhere and one on gpu-nvidia only
const CATALOGUE = {
  models: [
    { id: 'a', label: 'A', ollama: { model: 'a:1b', runtimes: ['gpu-nvidia'] }, vllm: { model: 'Org/A', args: '' } },
    { id: 'b', label: 'B', vllm: { model: 'Org/B', args: '', runtimes: ['gpu-nvidia'] } },
  ],
}

async function writeCatalogue(rootDir: string) {
  const dir = join(rootDir, 'compose', 'models')
  await mkdir(dir, { recursive: true })
  await writeFile(join(dir, 'models.json'), JSON.stringify(CATALOGUE))
}

const NVIDIA_LINE = 'x86_64|67353571328|16|Ubuntu|io.containerd.runc.v2,nvidia,runc,\n'
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

let rootDir: string

beforeEach(async () => {
  rootDir = await mkdtemp(join(tmpdir(), 'n8n-starter-config-'))
  introMock.mockReset()
  textMock.mockReset()
  selectMock.mockReset()
  multiselectMock.mockReset()
  logInfoMock.mockReset()
  logWarnMock.mockReset()
  logErrorMock.mockReset()
})

async function writeEnv(content = ENV_CONTENT) {
  const envPath = join(rootDir, '.env')
  await writeFile(envPath, content)
  return envPath
}

afterEach(async () => {
  await rm(rootDir, { recursive: true, force: true })
  process.exitCode = 0
  setLogLevel('info')
})

test('config schema accepts the template defaults and rejects invalid values', () => {
  expect(configSchema.safeParse(VALID_CONFIG).success).toBe(true)
  expect(configSchema.safeParse({ ...VALID_CONFIG, AI_ENGINE: 'vllm' }).success).toBe(true)
  // an empty AI_MODELS starts no model, a single entry needs no comma
  expect(configSchema.safeParse({ ...VALID_CONFIG, AI_MODELS: '' }).success).toBe(true)
  expect(configSchema.safeParse({ ...VALID_CONFIG, AI_MODELS: 'qwen3-5-0-8b' }).success).toBe(true)
  // ids are DNS labels, so no dots, no uppercase and no leading or trailing dash
  expect(configSchema.safeParse({ ...VALID_CONFIG, AI_MODELS: 'qwen3.5-0.8b' }).success).toBe(false)
  expect(configSchema.safeParse({ ...VALID_CONFIG, AI_MODELS: 'a-,b' }).success).toBe(false)
  // no gateway runs by default: a root .env without the key reads like an empty one
  expect(configSchema.parse(VALID_CONFIG).AI_GATEWAY).toBe('')
  expect(configSchema.safeParse({ ...VALID_CONFIG, AI_GATEWAY: '' }).success).toBe(true)
  expect(configSchema.safeParse({ ...VALID_CONFIG, AI_GATEWAY: 'litellm' }).success).toBe(true)
  expect(configSchema.safeParse({ ...VALID_CONFIG, AI_GATEWAY: 'kong' }).success).toBe(false)

  expect(configSchema.safeParse({ ...VALID_CONFIG, AI_RUNTIME: 'gpu-intel' }).success).toBe(false)
  expect(configSchema.safeParse({ ...VALID_CONFIG, AI_ENGINE: 'llamacpp' }).success).toBe(false)
  expect(configSchema.safeParse({ ...VALID_CONFIG, AI_MODELS: 'Qwen/Qwen3.5-0.8B' }).success).toBe(false)
  expect(configSchema.safeParse({ ...VALID_CONFIG, AI_MODELS: 'a,,b' }).success).toBe(false)
  expect(configSchema.safeParse({ ...VALID_CONFIG, N8N_VARIANT: 'pro' }).success).toBe(false)
})

test('the first option of every list is the default of the root .env.template', async () => {
  const template = parseEnvContent(await readFile(new URL('../../../.env.template', import.meta.url), 'utf-8'))

  expect(template.AI_RUNTIME).toBe(AI_RUNTIMES[0])
  expect(template.AI_ENGINE).toBe(AI_ENGINES[0])
  expect(template.N8N_VARIANT).toBe(N8N_VARIANTS[0])
  // no model starts with the stack by default, and no gateway
  expect(template.AI_MODELS).toBe('')
  expect(template.AI_GATEWAY).toBe('')
  expect(aiGatewaySchema.options).toEqual(['', ...AI_GATEWAYS])
})

test('the config keys and their descriptions mirror the root .env.template', async () => {
  const content = await readFile(new URL('../../../.env.template', import.meta.url), 'utf-8')

  // every key of the template is a config key, in template order (parseEnv sorts its keys, so the order comes
  // from the KEY= lines)
  const templateKeys = content.split('\n').map(line => line.match(/^([A-Z_][A-Z0-9_]*)=/)?.[1]).filter(key => key !== undefined)
  expect(templateKeys).toEqual([...CONFIG_KEYS])
  for (const key of CONFIG_KEYS) {
    // the description is the comment line right above the key
    const comment = content.split('\n').find(line => line.startsWith('#') && line.includes(CONFIG_KEY_DESCRIPTIONS[key]))
    expect(comment, `${key}: ${CONFIG_KEY_DESCRIPTIONS[key]}`).toBeDefined()
  }
})

test('domain schema rejects invalid hostnames', () => {
  expect(domainSchema.safeParse('n8n.localhost').success).toBe(true)
  expect(domainSchema.safeParse('').success).toBe(false)
  expect(domainSchema.safeParse('not a domain').success).toBe(false)
  expect(domainSchema.safeParse('-bad.localhost').success).toBe(false)
})

test('parseEnvContent reads keys and ignores comments', () => {
  expect(parseEnvContent(ENV_CONTENT)).toEqual({
    DOMAIN: 'n8n.localhost',
    AI_RUNTIME: 'cpu-arm64',
    AI_ENGINE: 'ollama',
    AI_GATEWAY: '',
    AI_MODELS: '',
    N8N_VARIANT: 'dev',
  })
})

test('updateEnvContent replaces values while preserving comments and appends missing keys', () => {
  const updated = updateEnvContent(ENV_CONTENT, {
    AI_RUNTIME: 'gpu-nvidia',
    NEW_KEY: 'value',
  })

  expect(updated).toContain('# Options: cpu-arm64, cpu-x86-64, gpu-nvidia or gpu-amd')
  expect(updated).toContain('AI_RUNTIME=gpu-nvidia')
  expect(updated).toContain('DOMAIN=n8n.localhost')
  expect(updated.endsWith('NEW_KEY=value\n')).toBe(true)
})

test('config without arguments asks which key, prompts only that key and writes it', async () => {
  const envPath = await writeEnv()
  await writeCatalogue(rootDir)
  selectMock.mockResolvedValueOnce('N8N_VARIANT').mockResolvedValueOnce('community')

  await config(rootDir)

  // every key is offered with its description and its available values, the current one highlighted
  expect(selectMock).toHaveBeenNthCalledWith(1, expect.objectContaining({
    options: CONFIG_KEYS.map(key => expect.objectContaining({ value: key, label: key, hint: expect.stringContaining(CONFIG_KEY_DESCRIPTIONS[key]) })),
  }))
  const hints = selectMock.mock.calls[0]![0].options.map((option: { hint: string }) => option.hint)
  // n8n first, the rarely changed DOMAIN last
  expect(hints[0]).toMatch(/dev.*community.*enterprise/)
  expect(hints.at(-1)).toMatch(/: .*n8n\.localhost/)
  expect(hints).toHaveLength(6)
  expect(selectMock).toHaveBeenNthCalledWith(2, expect.objectContaining({ initialValue: 'dev' }))
  expect(textMock).not.toHaveBeenCalled()
  expect(multiselectMock).not.toHaveBeenCalled()
  const updated = await readFile(envPath, 'utf-8')
  expect(parseEnvContent(updated)).toEqual({ ...parseEnvContent(ENV_CONTENT), N8N_VARIANT: 'community' })
  expect(updated).toContain('# Options: dev, build, community or enterprise')
})

test('keyHint lists the available values and marks the selected one', async () => {
  const { keyHint } = await import('../src/commands/config')
  const current = { ...parseEnvContent(ENV_CONTENT), AI_ENGINE: 'vllm' }

  expect(keyHint('AI_ENGINE', current).replace(/\u001B\[\d+m/g, '')).toBe(`${CONFIG_KEY_DESCRIPTIONS.AI_ENGINE}: ollama, vllm`)
  // an unknown current value is listed after the options
  expect(keyHint('N8N_VARIANT', { N8N_VARIANT: 'pro' }).replace(/\u001B\[\d+m/g, '')).toBe(`${CONFIG_KEY_DESCRIPTIONS.N8N_VARIANT}: dev, build, community, enterprise, pro`)
  expect(keyHint('DOMAIN', current).replace(/\u001B\[\d+m/g, '')).toBe(`${CONFIG_KEY_DESCRIPTIONS.DOMAIN}: n8n.localhost`)
  expect(keyHint('DOMAIN', {}).replace(/\u001B\[\d+m/g, '')).toBe(`${CONFIG_KEY_DESCRIPTIONS.DOMAIN}: none`)
  // the empty option of AI_GATEWAY reads none, also in a root .env without the key
  expect(keyHint('AI_GATEWAY', current).replace(/\u001B\[\d+m/g, '')).toBe(`${CONFIG_KEY_DESCRIPTIONS.AI_GATEWAY}: none, litellm`)
  expect(keyHint('AI_GATEWAY', {}).replace(/\u001B\[\d+m/g, '')).toBe(`${CONFIG_KEY_DESCRIPTIONS.AI_GATEWAY}: none, litellm`)
  // AI_MODELS shows its current list, the catalogue is left to the multi-select
  expect(keyHint('AI_MODELS', current).replace(/\u001B\[\d+m/g, '')).toBe(`${CONFIG_KEY_DESCRIPTIONS.AI_MODELS}: none`)
  expect(keyHint('AI_MODELS', { AI_MODELS: 'a,b' }).replace(/\u001B\[\d+m/g, '')).toBe(`${CONFIG_KEY_DESCRIPTIONS.AI_MODELS}: a,b`)
})

test('config AI_MODELS runs the multi-select of models select under the config intro and writes only AI_MODELS', async () => {
  const content = ENV_CONTENT.replace('AI_ENGINE=ollama', 'AI_ENGINE=vllm')
  const envPath = await writeEnv(content)
  await writeCatalogue(rootDir)
  multiselectMock.mockResolvedValueOnce(['a'])
  const { options, calls } = platform()

  await config(rootDir, ['AI_MODELS'], options)

  // the entries of the current engine, the ones the runtime cannot run disabled
  expect(multiselectMock).toHaveBeenCalledWith(expect.objectContaining({
    options: [expect.objectContaining({ value: 'a', disabled: false }), expect.objectContaining({ value: 'b', disabled: true })],
    initialValues: [],
  }))
  expect(selectMock).not.toHaveBeenCalled()
  // the prompt weighs the estimates against the docker memory
  expect(calls).toEqual([['info', '--format', DOCKER_INFO_FORMAT]])
  expect(await readFile(envPath, 'utf-8')).toBe(content.replace('AI_MODELS=', 'AI_MODELS=a'))
  expect(logInfoMock).toHaveBeenCalledWith(expect.stringContaining('a runs at http://vllm-a:8000/v1'))
  expect(introMock.mock.calls).toEqual([['n8n-starter config']])
  expect(process.exitCode).toBe(0)
})

test('config offers AI_MODELS in the key select and hands it to the multi-select', async () => {
  const envPath = await writeEnv(ENV_CONTENT.replace('AI_ENGINE=ollama', 'AI_ENGINE=vllm').replace('AI_MODELS=', 'AI_MODELS=a'))
  await writeCatalogue(rootDir)
  selectMock.mockResolvedValueOnce('AI_MODELS')
  multiselectMock.mockResolvedValueOnce([])

  await config(rootDir, [], platform().options)

  expect(selectMock).toHaveBeenCalledOnce()
  expect(multiselectMock).toHaveBeenCalledWith(expect.objectContaining({ initialValues: ['a'] }))
  expect(parseEnvContent(await readFile(envPath, 'utf-8')).AI_MODELS).toBe('')
  expect(introMock.mock.calls).toEqual([['n8n-starter config']])
})

test('config AI_MODELS ids writes without a prompt or a docker call and "" clears the list', async () => {
  const envPath = await writeEnv(ENV_CONTENT.replace('AI_ENGINE=ollama', 'AI_ENGINE=vllm'))
  await writeCatalogue(rootDir)
  const { options, calls } = platform()

  await config(rootDir, ['AI_MODELS', 'a'], options)
  expect(parseEnvContent(await readFile(envPath, 'utf-8')).AI_MODELS).toBe('a')

  await config(rootDir, ['AI_MODELS', ''], options)
  expect(parseEnvContent(await readFile(envPath, 'utf-8')).AI_MODELS).toBe('')

  expect(multiselectMock).not.toHaveBeenCalled()
  expect(selectMock).not.toHaveBeenCalled()
  expect(calls).toEqual([])
  expect(process.exitCode).toBe(0)
})

test('config AI_MODELS fails naming the catalogue when it is missing', async () => {
  const envPath = await writeEnv()

  await config(rootDir, ['AI_MODELS', 'a'])

  expect(logErrorMock).toHaveBeenCalledWith(expect.stringContaining('No model catalogue found'))
  expect(await readFile(envPath, 'utf-8')).toBe(ENV_CONTENT)
  expect(process.exitCode).toBe(1)
})

test('config AI_GATEWAY offers none first, writes the gateway and says where n8n reaches it', async () => {
  const envPath = await writeEnv()
  selectMock.mockResolvedValueOnce('litellm')

  await config(rootDir, ['AI_GATEWAY'])

  expect(selectMock).toHaveBeenCalledWith(expect.objectContaining({
    options: [{ value: '', label: 'none' }, { value: 'litellm', label: 'litellm' }],
    initialValue: '',
  }))
  expect(parseEnvContent(await readFile(envPath, 'utf-8')).AI_GATEWAY).toBe('litellm')
  expect(logInfoMock).toHaveBeenCalledWith('litellm serves every model of AI_MODELS under its id at http://litellm:4000/v1, bearer token LITELLM_MASTER_KEY of compose/models/litellm/.env')

  // an empty value turns the gateway off again, without a prompt and without an endpoint
  logInfoMock.mockReset()
  await config(rootDir, ['AI_GATEWAY', ''])

  expect(await readFile(envPath, 'utf-8')).toBe(ENV_CONTENT)
  expect(logInfoMock).not.toHaveBeenCalled()
  expect(process.exitCode).toBe(0)
})

test('config AI_GATEWAY appends the key to a root .env written before it existed', async () => {
  const content = ENV_CONTENT.replace(/# The gateway[^\n]*\n# Options: empty[^\n]*\nAI_GATEWAY=\n/, '')
  expect(content).not.toContain('AI_GATEWAY')
  const envPath = await writeEnv(content)

  await config(rootDir, ['AI_GATEWAY', 'litellm'])

  expect(await readFile(envPath, 'utf-8')).toBe(`${content}AI_GATEWAY=litellm\n`)
})

test('config DOMAIN prompts the domain only', async () => {
  const envPath = await writeEnv()
  textMock.mockResolvedValue('my.localhost')

  await config(rootDir, ['DOMAIN'])

  expect(textMock).toHaveBeenCalledWith(expect.objectContaining({ initialValue: 'n8n.localhost' }))
  expect(selectMock).not.toHaveBeenCalled()
  expect(parseEnvContent(await readFile(envPath, 'utf-8')).DOMAIN).toBe('my.localhost')
})

test('config KEY value writes without a prompt', async () => {
  const envPath = await writeEnv()

  await config(rootDir, ['N8N_VARIANT', 'enterprise'])

  expect(selectMock).not.toHaveBeenCalled()
  expect(textMock).not.toHaveBeenCalled()
  expect(parseEnvContent(await readFile(envPath, 'utf-8')).N8N_VARIANT).toBe('enterprise')
  expect(process.exitCode).toBe(0)
})

test.each([
  [['NOPE', 'x'], 'Unknown config key "NOPE"'],
  [['N8N_VARIANT', 'pro'], 'Invalid N8N_VARIANT "pro"'],
  [['DOMAIN', 'not a domain'], 'valid hostname'],
  [['AI_GATEWAY', 'kong'], 'Invalid AI_GATEWAY "kong": Gateway must be empty for none, or one of: litellm'],
  // AI_MODELS is validated by `models select`: the shape, then the catalogue of the engine on the runtime
  [['AI_MODELS', 'A/B'], 'Invalid AI_MODELS "A/B"'],
  [['AI_MODELS', 'b'], 'Invalid AI_MODELS "b": b: not served by vllm on cpu-arm64'],
])('config %j fails without writing or prompting', async (rest, message) => {
  const content = ENV_CONTENT.replace('AI_ENGINE=ollama', 'AI_ENGINE=vllm')
  const envPath = await writeEnv(content)
  await writeCatalogue(rootDir)

  await config(rootDir, rest)

  expect(logErrorMock).toHaveBeenCalledWith(expect.stringContaining(message))
  expect(selectMock).not.toHaveBeenCalled()
  expect(multiselectMock).not.toHaveBeenCalled()
  expect(await readFile(envPath, 'utf-8')).toBe(content)
  expect(process.exitCode).toBe(1)
})

test('config AI_ENGINE warns about models the new engine does not serve and keeps them', async () => {
  const envPath = await writeEnv(ENV_CONTENT.replace('AI_MODELS=', 'AI_MODELS=a,c'))
  await writeCatalogue(rootDir)

  await config(rootDir, ['AI_ENGINE', 'vllm'])

  const updated = parseEnvContent(await readFile(envPath, 'utf-8'))
  expect(updated.AI_ENGINE).toBe('vllm')
  expect(updated.AI_MODELS).toBe('a,c')
  expect(logWarnMock).toHaveBeenCalledWith(expect.stringContaining('c not served by vllm on cpu-arm64'))
  expect(logWarnMock).toHaveBeenCalledWith(expect.stringContaining('pnpm run models select'))
  expect(logInfoMock).toHaveBeenCalledWith(expect.stringContaining('a runs at http://vllm-a:8000/v1'))
})

test('config AI_RUNTIME does not warn when every model still runs and the runtime fits the platform', async () => {
  await writeEnv(ENV_CONTENT.replace('AI_MODELS=', 'AI_MODELS=a'))
  await writeCatalogue(rootDir)
  const { options, calls } = platform(NVIDIA_LINE)

  await config(rootDir, ['AI_RUNTIME', 'gpu-nvidia'], options)

  expect(logWarnMock).not.toHaveBeenCalled()
  expect(logInfoMock).toHaveBeenCalledWith('Detected docker x86_64, 16 cpus, 63 GB memory (Ubuntu), host linux/arm64 32 GB, nvidia gpu')
  expect(calls).toEqual([['info', '--format', DOCKER_INFO_FORMAT]])
})

test('config AI_RUNTIME warns about a value that does not match the detected platform and still writes it', async () => {
  const envPath = await writeEnv()
  await writeCatalogue(rootDir)

  await config(rootDir, ['AI_RUNTIME', 'cpu-x86-64'], platform().options)

  expect(parseEnvContent(await readFile(envPath, 'utf-8')).AI_RUNTIME).toBe('cpu-x86-64')
  expect(logWarnMock).toHaveBeenCalledWith('AI_RUNTIME=cpu-x86-64 does not match the detected platform (docker aarch64, 8 cpus, 16 GB memory (Docker Desktop), host linux/arm64 32 GB, no gpu), run `pnpm run config AI_RUNTIME cpu-arm64`')
  expect(process.exitCode).toBe(0)
})

test('config AI_RUNTIME marks the detected runtime in the prompt and keeps the current one preselected', async () => {
  const envPath = await writeEnv(ENV_CONTENT.replace('AI_RUNTIME=cpu-arm64', 'AI_RUNTIME=cpu-x86-64'))
  await writeCatalogue(rootDir)
  selectMock.mockResolvedValueOnce('cpu-arm64')

  await config(rootDir, ['AI_RUNTIME'], platform().options)

  // the mark lives in the label, not in a hint, so every row shows it (the colour only on a tty)
  const options = selectMock.mock.calls[0]![0].options as { value: string, label: string, hint?: string }[]
  expect(options.map(option => ({ ...option, label: stripVTControlCharacters(option.label) }))).toEqual(
    AI_RUNTIMES.map(value => ({ value, label: value === 'cpu-arm64' ? 'cpu-arm64 (detected)' : value })),
  )
  expect(selectMock).toHaveBeenCalledWith(expect.objectContaining({ initialValue: 'cpu-x86-64' }))
  expect(parseEnvContent(await readFile(envPath, 'utf-8')).AI_RUNTIME).toBe('cpu-arm64')
  expect(logWarnMock).not.toHaveBeenCalled()
})

test('config never asks docker for a key other than AI_RUNTIME', async () => {
  await writeEnv()
  await writeCatalogue(rootDir)
  const { options, calls } = platform()
  selectMock.mockResolvedValueOnce('vllm')

  await config(rootDir, ['N8N_VARIANT', 'community'], options)
  await config(rootDir, ['AI_ENGINE'], options)

  expect(calls).toEqual([])
  expect(logInfoMock).not.toHaveBeenCalledWith(expect.stringContaining('Detected'))
})

test('config AI_ENGINE warns when the model catalogue is missing and still writes', async () => {
  const envPath = await writeEnv()

  await config(rootDir, ['AI_ENGINE', 'vllm'])

  expect(logWarnMock).toHaveBeenCalledWith(expect.stringContaining('No model catalogue found'))
  expect(parseEnvContent(await readFile(envPath, 'utf-8')).AI_ENGINE).toBe('vllm')
  expect(process.exitCode).toBe(0)
})

test('config leaves the .env file untouched when a prompt is cancelled', async () => {
  const envPath = await writeEnv()
  selectMock.mockResolvedValue(CANCEL)

  await config(rootDir)
  await config(rootDir, ['AI_ENGINE'])

  expect(await readFile(envPath, 'utf-8')).toBe(ENV_CONTENT)
})

test('config AI_MODELS leaves the .env file untouched when the multi-select is cancelled', async () => {
  const content = ENV_CONTENT.replace('AI_ENGINE=ollama', 'AI_ENGINE=vllm').replace('AI_MODELS=', 'AI_MODELS=a')
  const envPath = await writeEnv(content)
  await writeCatalogue(rootDir)
  multiselectMock.mockResolvedValue(CANCEL)

  await config(rootDir, ['AI_MODELS'], platform().options)

  expect(multiselectMock).toHaveBeenCalledOnce()
  expect(await readFile(envPath, 'utf-8')).toBe(content)
  expect(process.exitCode).toBe(0)
})

test('config fails without writing when no .env file exists', async () => {
  await config(rootDir)

  expect(selectMock).not.toHaveBeenCalled()
  expect(existsSync(join(rootDir, '.env'))).toBe(false)
  expect(process.exitCode).toBe(1)
})

test('config still reports the missing .env file at the error log level', async () => {
  setLogLevel('error')

  await config(rootDir)

  expect(logErrorMock).toHaveBeenCalledWith(expect.stringContaining('No .env file found'))
  expect(process.exitCode).toBe(1)
})

test('config warns about a human secret the new value requires and points at secrets set', async () => {
  await writeEnv()
  const dir = join(rootDir, 'compose', 'n8n')
  await mkdir(dir, { recursive: true })
  await writeFile(join(dir, '.env.template'), 'N8N_LICENSE_ACTIVATION_KEY=\n')
  await writeFile(join(dir, '.env'), 'N8N_LICENSE_ACTIVATION_KEY=\n')
  await writeFile(join(dir, '.env.secrets.json'), JSON.stringify({ secrets: { N8N_LICENSE_ACTIVATION_KEY: { source: 'prompt', description: 'license', required: { N8N_VARIANT: ['enterprise'] } } } }))

  await config(rootDir, ['N8N_VARIANT', 'enterprise'])

  expect(logWarnMock).toHaveBeenCalledWith('N8N_LICENSE_ACTIVATION_KEY in compose/n8n/.env is required for N8N_VARIANT=enterprise, run `pnpm run secrets set N8N_LICENSE_ACTIVATION_KEY`')

  logWarnMock.mockReset()
  await config(rootDir, ['N8N_VARIANT', 'community'])

  expect(logWarnMock).not.toHaveBeenCalled()
})
