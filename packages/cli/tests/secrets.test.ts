import { existsSync } from 'node:fs'
import { mkdir, mkdtemp, readdir, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { stripVTControlCharacters } from 'node:util'
import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import { AI_ENGINES, AI_RUNTIMES, N8N_VARIANTS } from '../src/schemas/config'
import { SECRET_ENCODINGS, SECRET_KEY_PATTERN, SECRET_PREFIX_PATTERN, SECRET_ROTATIONS, SECRET_SOURCES, secretsManifestSchema } from '../src/schemas/secrets'
import { parseEnvContent } from '../src/utils/env'
import { setLogLevel } from '../src/utils/logger'

const { passwordMock, logWarnMock, logErrorMock, logSuccessMock, cancelMock, CANCEL } = vi.hoisted(() => ({
  passwordMock: vi.fn(),
  logWarnMock: vi.fn(),
  logErrorMock: vi.fn(),
  logSuccessMock: vi.fn(),
  cancelMock: vi.fn(),
  CANCEL: Symbol('clack-cancel'),
}))

vi.mock('@clack/prompts', () => ({
  intro: vi.fn(),
  outro: vi.fn(),
  cancel: cancelMock,
  password: passwordMock,
  isCancel: (value: unknown) => value === CANCEL,
  log: { info: vi.fn(), warn: logWarnMock, success: logSuccessMock, error: logErrorMock, step: vi.fn(), message: vi.fn() },
}))

const { checkSecrets, fillSecrets, generateSecret, isUnfilled, listSecrets, readSecretManifests, readSecretState, requiredBy, secrets, setSecret } = await import('../src/commands/secrets')

// three directories: postgres generates the password n8n links to, n8n prompts for the enterprise license,
// vllm generates a prefixed key and has an optional token the template keeps commented out
const POSTGRES_MANIFEST = { secrets: { POSTGRES_PASSWORD: { source: 'generate', rotation: 'manual', description: 'db password' } } }
const N8N_MANIFEST = { secrets: {
  N8N_ENCRYPTION_KEY: { source: 'generate', rotation: 'never', description: 'encryption key' },
  DB_POSTGRESDB_PASSWORD: { source: 'link', from: '../storage/postgres', key: 'POSTGRES_PASSWORD' },
  N8N_LICENSE_ACTIVATION_KEY: { source: 'prompt', description: 'license key', required: { N8N_VARIANT: ['enterprise'] } },
} }
const VLLM_MANIFEST = { secrets: {
  VLLM_API_KEY: { source: 'generate', description: 'api key', prefix: 'sk-', bytes: 16, encoding: 'base64url' },
  HF_TOKEN: { source: 'prompt', description: 'hf token' },
} }
const POSTGRES_TEMPLATE = '# postgres\nPOSTGRES_USER=changeUser\nPOSTGRES_PASSWORD=\n'
const N8N_TEMPLATE = 'N8N_VERSION=1\nN8N_LICENSE_ACTIVATION_KEY=\n# secrets\nN8N_ENCRYPTION_KEY=\nDB_POSTGRESDB_USER=changeUser\nDB_POSTGRESDB_PASSWORD=\n'
const VLLM_TEMPLATE = 'VLLM_API_KEY=\n# HF_TOKEN=\n'
const ROOT_ENV = 'DOMAIN=n8n.localhost\nN8N_VARIANT=dev\nAI_RUNTIME=cpu-arm64\nAI_ENGINE=ollama\nAI_MODELS=\n'

const CONFIG = { DOMAIN: 'n8n.localhost', N8N_VARIANT: 'dev', AI_RUNTIME: 'cpu-arm64', AI_ENGINE: 'ollama', AI_GATEWAY: '', AI_MODELS: '' } as const
const ENTERPRISE = { ...CONFIG, N8N_VARIANT: 'enterprise' } as const

let rootDir: string
let previousExitCode: typeof process.exitCode
let logSpy: ReturnType<typeof vi.spyOn>

beforeEach(async () => {
  rootDir = await mkdtemp(join(tmpdir(), 'n8n-starter-secrets-'))
  previousExitCode = process.exitCode
  logSpy = vi.spyOn(console, 'log').mockImplementation(() => {})
  passwordMock.mockReset()
  logWarnMock.mockReset()
  logErrorMock.mockReset()
  logSuccessMock.mockReset()
  cancelMock.mockReset()
})

afterEach(async () => {
  await rm(rootDir, { recursive: true, force: true })
  process.exitCode = previousExitCode
  logSpy.mockRestore()
  setLogLevel('info')
})

async function addDir(dir: string, files: Record<string, string | object>) {
  const fullDir = join(rootDir, dir)
  await mkdir(fullDir, { recursive: true })
  for (const [name, content] of Object.entries(files))
    await writeFile(join(fullDir, name), typeof content === 'string' ? content : JSON.stringify(content))
  return fullDir
}

/** The three directories, each with its manifest and template, and a .env copied from the template unless `env` is false */
async function fixture({ env = true, rootEnv = ROOT_ENV } = {}) {
  await writeFile(join(rootDir, '.env'), rootEnv)
  const dirs = {
    postgres: await addDir('compose/storage/postgres', { '.env.template': POSTGRES_TEMPLATE, '.env.secrets.json': POSTGRES_MANIFEST, ...(env ? { '.env': POSTGRES_TEMPLATE } : {}) }),
    n8n: await addDir('compose/n8n', { '.env.template': N8N_TEMPLATE, '.env.secrets.json': N8N_MANIFEST, ...(env ? { '.env': N8N_TEMPLATE } : {}) }),
    vllm: await addDir('compose/models/vllm', { '.env.template': VLLM_TEMPLATE, '.env.secrets.json': VLLM_MANIFEST, ...(env ? { '.env': VLLM_TEMPLATE } : {}) }),
  }
  return dirs
}

async function env(dir: string): Promise<Record<string, string>> {
  return parseEnvContent(await readFile(join(dir, '.env'), 'utf-8'))
}

test('reads every manifest with its defaults and resolves the links', async () => {
  await fixture()

  const declared = await readSecretManifests(rootDir)

  expect(declared.map(secret => `${relative(rootDir, secret.dir)}:${secret.key}`)).toEqual([
    'compose/models/vllm:VLLM_API_KEY',
    'compose/models/vllm:HF_TOKEN',
    'compose/n8n:N8N_ENCRYPTION_KEY',
    'compose/n8n:DB_POSTGRESDB_PASSWORD',
    'compose/n8n:N8N_LICENSE_ACTIVATION_KEY',
    'compose/storage/postgres:POSTGRES_PASSWORD',
  ])
  expect(declared.find(secret => secret.key === 'N8N_ENCRYPTION_KEY')!.entry).toEqual({ source: 'generate', rotation: 'never', description: 'encryption key', bytes: 32, encoding: 'hex', prefix: '' })
  expect(declared.find(secret => secret.key === 'VLLM_API_KEY')!.entry).toMatchObject({ rotation: 'free', prefix: 'sk-', bytes: 16, encoding: 'base64url' })
})

test.each([
  ['an unknown source', { secrets: { KEY: { source: 'random', description: 'x' } } }],
  ['an unknown field', { secrets: { KEY: { source: 'generate', description: 'x', length: 3 } } }],
  ['a missing description', { secrets: { KEY: { source: 'generate' } } }],
  ['a lower case key', { secrets: { key: { source: 'generate', description: 'x' } } }],
  ['no secrets', { secrets: {} }],
  ['too few bytes', { secrets: { KEY: { source: 'generate', description: 'x', bytes: 8 } } }],
  ['a prefix with spaces', { secrets: { KEY: { source: 'generate', description: 'x', prefix: 'sk ' } } }],
  ['a required condition on an unknown root key', { secrets: { KEY: { source: 'prompt', description: 'x', required: { DOMAIN: ['a'] } } } }],
  ['a required condition with an unknown value', { secrets: { KEY: { source: 'prompt', description: 'x', required: { N8N_VARIANT: ['pro'] } } } }],
  ['an empty required condition', { secrets: { KEY: { source: 'prompt', description: 'x', required: {} } } }],
  ['an absolute link', { secrets: { KEY: { source: 'link', from: '/etc', key: 'OTHER' } } }],
  ['a top-level field', { secrets: { KEY: { source: 'generate', description: 'x' } }, extra: true }],
])('the manifest schema rejects %s', (_, manifest) => {
  expect(secretsManifestSchema.safeParse(manifest).success).toBe(false)
})

test('rejects a link to a key no manifest declares', async () => {
  await addDir('compose/n8n', { '.env.template': 'A=\n', '.env.secrets.json': { secrets: { A: { source: 'link', from: '../storage/postgres', key: 'B' } } } })

  await expect(readSecretManifests(rootDir)).rejects.toThrow('compose/n8n/.env.secrets.json: A links to B of compose/storage/postgres, which no .env.secrets.json declares')
})

test('rejects a link to a link', async () => {
  await addDir('compose/a', { '.env.template': 'A=\n', '.env.secrets.json': { secrets: { A: { source: 'link', from: '../b', key: 'B' } } } })
  await addDir('compose/b', { '.env.template': 'B=\n', '.env.secrets.json': { secrets: { B: { source: 'link', from: '../c', key: 'C' } } } })
  await addDir('compose/c', { '.env.template': 'C=\n', '.env.secrets.json': { secrets: { C: { source: 'generate', description: 'c' } } } })

  await expect(readSecretManifests(rootDir)).rejects.toThrow('compose/a/.env.secrets.json: A links to B of compose/b, which is a link itself')
})

test('rejects an invalid manifest naming the file', async () => {
  await addDir('compose/a', { '.env.template': 'A=\n', '.env.secrets.json': '{ not json' })

  await expect(readSecretManifests(rootDir)).rejects.toThrow(join(rootDir, 'compose/a/.env.secrets.json'))
})

test('rejects a manifest without a template next to it', async () => {
  await addDir('compose/a', { '.env.secrets.json': { secrets: { A: { source: 'generate', description: 'a' } } } })

  await expect(readSecretState(rootDir)).rejects.toThrow('No .env.template next to compose/a/.env.secrets.json')
})

test('a secret is unfilled while absent, empty or still the template value', () => {
  expect(isUnfilled(undefined, '')).toBe(true)
  expect(isUnfilled('', '')).toBe(true)
  expect(isUnfilled('changePassword', 'changePassword')).toBe(true)
  expect(isUnfilled('abc', '')).toBe(false)
  expect(isUnfilled('abc', undefined)).toBe(false)
})

test('generates random values of the requested shape', () => {
  const hex = generateSecret({ source: 'generate', description: 'x', rotation: 'free', bytes: 32, encoding: 'hex', prefix: '' })
  const prefixed = generateSecret({ source: 'generate', description: 'x', rotation: 'free', bytes: 16, encoding: 'base64url', prefix: 'sk-' })

  expect(hex).toMatch(/^[0-9a-f]{64}$/)
  expect(prefixed).toMatch(/^sk-[A-Za-z0-9_-]{22}$/)
  expect(generateSecret({ source: 'generate', description: 'x', rotation: 'free', bytes: 32, encoding: 'hex', prefix: '' })).not.toBe(hex)
})

test('a prompt secret is required only while every listed root value matches', () => {
  const license = N8N_MANIFEST.secrets.N8N_LICENSE_ACTIVATION_KEY as any
  const both = { source: 'prompt', description: 'x', required: { N8N_VARIANT: ['enterprise', 'community'], AI_ENGINE: ['vllm'] } } as any

  expect(requiredBy(license, ENTERPRISE)).toBe('N8N_VARIANT=enterprise')
  expect(requiredBy(license, CONFIG)).toBeUndefined()
  expect(requiredBy({ source: 'prompt', description: 'x' }, ENTERPRISE)).toBeUndefined()
  expect(requiredBy(both, ENTERPRISE)).toBeUndefined()
  expect(requiredBy(both, { ...ENTERPRISE, AI_ENGINE: 'vllm' })).toBe('N8N_VARIANT=enterprise, AI_ENGINE=vllm')
})

test('fills the generated secrets once and copies the links, keeping comments and other keys', async () => {
  const dirs = await fixture()

  const results = await fillSecrets(rootDir)

  expect(results.map(result => `${result.status} ${result.key}`)).toEqual([
    'generated VLLM_API_KEY',
    'generated N8N_ENCRYPTION_KEY',
    'generated POSTGRES_PASSWORD',
    'linked DB_POSTGRESDB_PASSWORD',
  ])
  const postgres = await env(dirs.postgres)
  const n8n = await env(dirs.n8n)
  const vllm = await env(dirs.vllm)
  expect(postgres.POSTGRES_PASSWORD).toMatch(/^[0-9a-f]{64}$/)
  expect(n8n.N8N_ENCRYPTION_KEY).toMatch(/^[0-9a-f]{64}$/)
  expect(n8n.N8N_ENCRYPTION_KEY).not.toBe(postgres.POSTGRES_PASSWORD)
  expect(n8n.DB_POSTGRESDB_PASSWORD).toBe(postgres.POSTGRES_PASSWORD)
  expect(n8n.N8N_LICENSE_ACTIVATION_KEY).toBe('')
  expect(vllm.VLLM_API_KEY).toMatch(/^sk-[A-Za-z0-9_-]{22}$/)
  expect(vllm.HF_TOKEN).toBeUndefined()
  const content = await readFile(join(dirs.n8n, '.env'), 'utf-8')
  expect(content.startsWith('N8N_VERSION=1\nN8N_LICENSE_ACTIVATION_KEY=\n# secrets\nN8N_ENCRYPTION_KEY=')).toBe(true)
  expect(content).toContain('DB_POSTGRESDB_USER=changeUser\n')
  // the templates stay untouched
  expect(await readFile(join(dirs.n8n, '.env.template'), 'utf-8')).toBe(N8N_TEMPLATE)

  expect(await fillSecrets(rootDir)).toEqual([])
  expect(await readFile(join(dirs.n8n, '.env'), 'utf-8')).toBe(content)
})

test('treats a value still equal to the template as unfilled', async () => {
  const dir = await addDir('compose/storage/postgres', {
    '.env.template': 'POSTGRES_PASSWORD=changePassword\n',
    '.env.secrets.json': POSTGRES_MANIFEST,
    '.env': 'POSTGRES_PASSWORD=changePassword\n',
  })

  const results = await fillSecrets(rootDir)

  expect(results).toEqual([{ envPath: join(dir, '.env'), key: 'POSTGRES_PASSWORD', status: 'generated' }])
  expect((await env(dir)).POSTGRES_PASSWORD).toMatch(/^[0-9a-f]{64}$/)
})

test('appends a secret key an older .env does not have', async () => {
  const dir = await addDir('compose/storage/postgres', { '.env.template': POSTGRES_TEMPLATE, '.env.secrets.json': POSTGRES_MANIFEST, '.env': 'POSTGRES_USER=changeUser\n' })

  await fillSecrets(rootDir)

  expect(await readFile(join(dir, '.env'), 'utf-8')).toMatch(/^POSTGRES_USER=changeUser\nPOSTGRES_PASSWORD=[0-9a-f]{64}\n$/)
})

test('repairs a link whose source was set by hand', async () => {
  const dirs = await fixture()
  await fillSecrets(rootDir)
  await writeFile(join(dirs.postgres, '.env'), 'POSTGRES_USER=changeUser\nPOSTGRES_PASSWORD=byhand\n')

  const results = await fillSecrets(rootDir)

  expect(results).toEqual([{ envPath: join(dirs.n8n, '.env'), key: 'DB_POSTGRESDB_PASSWORD', status: 'linked' }])
  expect((await env(dirs.n8n)).DB_POSTGRESDB_PASSWORD).toBe('byhand')
})

test('leaves a directory without a .env alone and skips a link whose source is unset', async () => {
  const dirs = await fixture({ env: false })
  await writeFile(join(dirs.n8n, '.env'), N8N_TEMPLATE)

  const results = await fillSecrets(rootDir)

  expect(results).toEqual([{ envPath: join(dirs.n8n, '.env'), key: 'N8N_ENCRYPTION_KEY', status: 'generated' }])
  expect(existsSync(join(dirs.postgres, '.env'))).toBe(false)
  expect((await env(dirs.n8n)).DB_POSTGRESDB_PASSWORD).toBe('')
})

test('checks every secret of the directories that have a .env', async () => {
  const dirs = await fixture()

  const before = checkSecrets(await readSecretState(rootDir), CONFIG)
  expect(before.map(check => `${check.key} ${check.status}`)).toEqual([
    'VLLM_API_KEY missing',
    'HF_TOKEN unset',
    'N8N_ENCRYPTION_KEY missing',
    'DB_POSTGRESDB_PASSWORD missing',
    'N8N_LICENSE_ACTIVATION_KEY unset',
    'POSTGRES_PASSWORD missing',
  ])
  expect(before.find(check => check.key === 'DB_POSTGRESDB_PASSWORD')!.source).toEqual({ envPath: join(dirs.postgres, '.env'), key: 'POSTGRES_PASSWORD' })

  await fillSecrets(rootDir)
  const enterprise = checkSecrets(await readSecretState(rootDir), ENTERPRISE)
  expect(enterprise.map(check => `${check.key} ${check.status}`)).toEqual([
    'VLLM_API_KEY ok',
    'HF_TOKEN unset',
    'N8N_ENCRYPTION_KEY ok',
    'DB_POSTGRESDB_PASSWORD ok',
    'N8N_LICENSE_ACTIVATION_KEY required',
    'POSTGRES_PASSWORD ok',
  ])
  expect(enterprise.find(check => check.key === 'N8N_LICENSE_ACTIVATION_KEY')!.condition).toBe('N8N_VARIANT=enterprise')

  // without the root config the conditions cannot be evaluated
  expect(checkSecrets(await readSecretState(rootDir)).find(check => check.key === 'N8N_LICENSE_ACTIVATION_KEY')!.status).toBe('unset')

  await writeFile(join(dirs.postgres, '.env'), 'POSTGRES_USER=changeUser\nPOSTGRES_PASSWORD=changed\n')
  expect(checkSecrets(await readSecretState(rootDir), CONFIG).find(check => check.key === 'DB_POSTGRESDB_PASSWORD')!.status).toBe('mismatch')

  await rm(join(dirs.vllm, '.env'))
  expect(checkSecrets(await readSecretState(rootDir), CONFIG).map(check => check.key)).not.toContain('VLLM_API_KEY')
})

test('lists the secrets whose directory or key contains the filter', async () => {
  await fixture()
  await fillSecrets(rootDir)
  const state = await readSecretState(rootDir)

  expect(listSecrets(state).map(secret => secret.key)).toHaveLength(6)
  expect(listSecrets(state, 'VLLM').map(secret => secret.key)).toEqual(['VLLM_API_KEY', 'HF_TOKEN'])
  expect(listSecrets(state, 'password').map(secret => secret.key)).toEqual(['DB_POSTGRESDB_PASSWORD', 'POSTGRES_PASSWORD'])
  expect(listSecrets(state, 'nothing')).toEqual([])
  expect(listSecrets(state, 'hf')[0]!.value).toBeUndefined()
})

test('sets a secret and copies it to its links', async () => {
  const dirs = await fixture()
  await fillSecrets(rootDir)

  const results = await setSecret(await readSecretState(rootDir), 'POSTGRES_PASSWORD', 'chosen')

  expect(results).toEqual([
    { envPath: join(dirs.postgres, '.env'), key: 'POSTGRES_PASSWORD', status: 'set' },
    { envPath: join(dirs.n8n, '.env'), key: 'DB_POSTGRESDB_PASSWORD', status: 'linked' },
  ])
  expect((await env(dirs.postgres)).POSTGRES_PASSWORD).toBe('chosen')
  expect((await env(dirs.n8n)).DB_POSTGRESDB_PASSWORD).toBe('chosen')
  await expect(setSecret(await readSecretState(rootDir), 'NOPE', 'x')).rejects.toThrow('Unknown secret "NOPE"')
})

test('secrets read prints the secrets grouped by .env, the keys in cyan on a tty, and nothing else', async () => {
  const dirs = await fixture()
  await fillSecrets(rootDir)
  const n8n = await env(dirs.n8n)
  const vllm = await env(dirs.vllm)

  await secrets(rootDir, ['read'])

  expect(logSpy).toHaveBeenCalledOnce()
  // the keys carry colour codes only when the runner forces colours
  expect(stripVTControlCharacters(logSpy.mock.calls[0]![0] as string)).toBe([
    'compose/models/vllm/.env',
    `VLLM_API_KEY=${vllm.VLLM_API_KEY}`,
    'HF_TOKEN=',
    '',
    'compose/n8n/.env',
    `N8N_ENCRYPTION_KEY=${n8n.N8N_ENCRYPTION_KEY}`,
    `DB_POSTGRESDB_PASSWORD=${n8n.DB_POSTGRESDB_PASSWORD}`,
    'N8N_LICENSE_ACTIVATION_KEY=',
    '',
    'compose/storage/postgres/.env',
    `POSTGRES_PASSWORD=${n8n.DB_POSTGRESDB_PASSWORD}`,
  ].join('\n'))
  expect(process.exitCode).toBe(previousExitCode)
})

test('secrets read filters by directory or key and prints only the value of an exact key', async () => {
  const dirs = await fixture()
  await fillSecrets(rootDir)
  const vllm = await env(dirs.vllm)

  await secrets(rootDir, ['read', 'vllm'])
  await secrets(rootDir, ['read', 'vllm_api_key'])

  expect(logSpy.mock.calls.map((call: unknown[]) => stripVTControlCharacters(call[0] as string))).toEqual([
    `compose/models/vllm/.env\nVLLM_API_KEY=${vllm.VLLM_API_KEY}\nHF_TOKEN=`,
    vllm.VLLM_API_KEY,
  ])
})

test.each([
  [['read', 'nothing'], 'No secret matches "nothing"'],
  [['nope'], 'Unknown sub-command "nope" for secrets. Expected one of: read, set'],
  [[], 'Missing sub-command for secrets. Expected one of: read, set'],
])('secrets %j exits with code 1: %s', async (argv, message) => {
  await fixture()

  await secrets(rootDir, argv)

  expect(logErrorMock).toHaveBeenCalledWith(expect.stringContaining(message))
  expect(logSpy).not.toHaveBeenCalled()
  expect(process.exitCode).toBe(1)
})

test('secrets read points at setup when a .env is missing', async () => {
  await fixture({ env: false })

  await secrets(rootDir, ['read', 'vllm'])

  expect(logErrorMock).toHaveBeenCalledWith('No compose/models/vllm/.env file found. Run `pnpm run setup` first.')
  expect(process.exitCode).toBe(1)
})

test('secrets set writes a given value without a prompt and copies it to the links', async () => {
  const dirs = await fixture()
  await fillSecrets(rootDir)

  await secrets(rootDir, ['set', 'POSTGRES_PASSWORD', 'chosen'])

  expect(passwordMock).not.toHaveBeenCalled()
  expect((await env(dirs.postgres)).POSTGRES_PASSWORD).toBe('chosen')
  expect((await env(dirs.n8n)).DB_POSTGRESDB_PASSWORD).toBe('chosen')
  expect(logSuccessMock.mock.calls.map(call => call[0])).toEqual([
    'POSTGRES_PASSWORD set in compose/storage/postgres/.env',
    'DB_POSTGRESDB_PASSWORD linked in compose/n8n/.env',
  ])
  expect(process.exitCode).toBe(previousExitCode)
})

test('secrets set asks with a masked prompt and appends a key the template keeps commented out', async () => {
  const dirs = await fixture()
  passwordMock.mockResolvedValue('hf_abc')

  await secrets(rootDir, ['set', 'HF_TOKEN'])

  expect(passwordMock).toHaveBeenCalledWith(expect.objectContaining({ message: 'hf token' }))
  expect(await readFile(join(dirs.vllm, '.env'), 'utf-8')).toBe('VLLM_API_KEY=\n# HF_TOKEN=\nHF_TOKEN=hf_abc\n')
  // the value never reaches the log
  expect(logSuccessMock.mock.calls.flat().join()).not.toContain('hf_abc')
})

test('secrets set keeps the file when the prompt is cancelled', async () => {
  const dirs = await fixture()
  passwordMock.mockResolvedValue(CANCEL)

  await secrets(rootDir, ['set', 'N8N_LICENSE_ACTIVATION_KEY'])

  expect(cancelMock).toHaveBeenCalled()
  expect(await readFile(join(dirs.n8n, '.env'), 'utf-8')).toBe(N8N_TEMPLATE)
  expect(process.exitCode).toBe(previousExitCode)
})

test('secrets set warns before replacing a secret the data depends on', async () => {
  const dirs = await fixture()
  await fillSecrets(rootDir)

  await secrets(rootDir, ['set', 'N8N_ENCRYPTION_KEY', 'restored'])

  expect(logWarnMock).toHaveBeenCalledWith('N8N_ENCRYPTION_KEY in compose/n8n/.env is already set and the data in .volumes/ depends on it')
  expect((await env(dirs.n8n)).N8N_ENCRYPTION_KEY).toBe('restored')
})

test.each([
  [['set', 'DB_POSTGRESDB_PASSWORD', 'x'], 'DB_POSTGRESDB_PASSWORD is a copy of POSTGRES_PASSWORD in compose/storage/postgres/.env, run `pnpm run secrets set POSTGRES_PASSWORD`'],
  [['set', 'NOPE', 'x'], 'Unknown secret "NOPE". Expected one of: VLLM_API_KEY, HF_TOKEN, N8N_ENCRYPTION_KEY, N8N_LICENSE_ACTIVATION_KEY, POSTGRES_PASSWORD'],
  [['set'], 'Missing secret key. Expected one of: VLLM_API_KEY, HF_TOKEN, N8N_ENCRYPTION_KEY, N8N_LICENSE_ACTIVATION_KEY, POSTGRES_PASSWORD'],
  [['set', 'POSTGRES_PASSWORD', ''], 'Invalid POSTGRES_PASSWORD: the value must not be empty'],
])('secrets %j exits with code 1 without writing', async (argv, message) => {
  const dirs = await fixture()

  await secrets(rootDir, argv)

  expect(logErrorMock).toHaveBeenCalledWith(message)
  expect(passwordMock).not.toHaveBeenCalled()
  expect(await readFile(join(dirs.n8n, '.env'), 'utf-8')).toBe(N8N_TEMPLATE)
  expect(await readFile(join(dirs.postgres, '.env'), 'utf-8')).toBe(POSTGRES_TEMPLATE)
  expect(process.exitCode).toBe(1)
})

test('secrets set points at setup when the .env is missing', async () => {
  await fixture({ env: false })

  await secrets(rootDir, ['set', 'POSTGRES_PASSWORD', 'x'])

  expect(logErrorMock).toHaveBeenCalledWith('No compose/storage/postgres/.env file found. Run `pnpm run setup` first.')
  expect(process.exitCode).toBe(1)
})

test('the repository manifests match their templates, their compose files and the editor schema', async () => {
  const repoRoot = fileURLToPath(new URL('../../../', import.meta.url))
  const state = await readSecretState(repoRoot)

  expect([...state.directories.keys()].map(dir => relative(repoRoot, dir))).toEqual([
    'compose/models/litellm',
    'compose/models/vllm',
    'compose/n8n',
    'compose/storage/pgadmin',
    'compose/storage/postgres',
  ])

  for (const secret of state.declared) {
    const directory = state.directories.get(secret.dir)!
    const where = `${secret.key} of ${relative(repoRoot, secret.dir)}`
    const template = await readFile(join(secret.dir, '.env.template'), 'utf-8')
    const composeFiles = (await readdir(secret.dir)).filter(name => /^docker-compose.*\.yml$/.test(name))
    const compose = (await Promise.all(composeFiles.map(name => readFile(join(secret.dir, name), 'utf-8')))).join('\n')
    if (secret.entry.source === 'prompt' && secret.entry.required === undefined) {
      // optional human secrets stay commented out in the template and optional in the compose file
      expect(directory.template[secret.key], where).toBeUndefined()
      expect(template, where).toContain(`# ${secret.key}=`)
      expect(compose, where).toContain(`\${${secret.key}:-`)
    } else {
      // everything setup fills or verify requires is live and empty, and the compose file refuses to start without it
      expect(directory.template[secret.key], where).toBe('')
      expect(compose, where).toContain(`\${${secret.key}:?}`)
    }
  }

  // every live empty key of a directory with a manifest is declared
  for (const directory of state.directories.values()) {
    for (const [key, value] of Object.entries(directory.template)) {
      if (value === '')
        expect(state.declared.some(secret => secret.dir === directory.dir && secret.key === key), `${key} of ${relative(repoRoot, directory.dir)} declared`).toBe(true)
    }
  }

  // every required secret-looking interpolation of the catalogue has a manifest entry in its directory
  const composeRoot = join(repoRoot, 'compose')
  const composeFiles = (await readdir(composeRoot, { recursive: true })).filter(path => /(^|\/)docker-compose[^/]*\.yml$/.test(path) && !path.includes('node_modules'))
  expect(composeFiles.length).toBeGreaterThan(5)
  for (const file of composeFiles) {
    const content = await readFile(join(composeRoot, file), 'utf-8')
    for (const [, name] of content.matchAll(/\$\{([A-Z0-9_]+):\?\}/g)) {
      if (/(PASSWORD|SECRET|_KEY|TOKEN)/.test(name!))
        expect(state.declared.some(secret => secret.dir === join(composeRoot, file, '..') && secret.key === name), `${name} of compose/${file} declared`).toBe(true)
    }
  }

  // the editor schema enforces the same keys, sources, rotations, encodings and conditions as the zod schema
  const schema = JSON.parse(await readFile(join(composeRoot, '.env.secrets.schema.json'), 'utf-8'))
  expect(schema.properties.secrets.propertyNames.pattern).toBe(SECRET_KEY_PATTERN.source)
  expect(schema.$defs.link.properties.key.pattern).toBe(SECRET_KEY_PATTERN.source)
  expect(schema.$defs.entry.oneOf.map((ref: { $ref: string }) => ref.$ref.split('/').pop())).toEqual([...SECRET_SOURCES])
  expect(schema.$defs.generate.properties.rotation.enum).toEqual([...SECRET_ROTATIONS])
  expect(schema.$defs.generate.properties.encoding.enum).toEqual([...SECRET_ENCODINGS])
  expect(schema.$defs.generate.properties.prefix.pattern).toBe(SECRET_PREFIX_PATTERN.source)
  expect(schema.$defs.prompt.properties.required.properties.N8N_VARIANT.items.enum).toEqual([...N8N_VARIANTS])
  expect(schema.$defs.prompt.properties.required.properties.AI_ENGINE.items.enum).toEqual([...AI_ENGINES])
  expect(schema.$defs.prompt.properties.required.properties.AI_RUNTIME.items.enum).toEqual([...AI_RUNTIMES])
  for (const dir of state.directories.keys()) {
    const manifest = JSON.parse(await readFile(join(dir, '.env.secrets.json'), 'utf-8'))
    expect(resolve(dir, manifest.$schema), relative(repoRoot, dir)).toBe(join(composeRoot, '.env.secrets.schema.json'))
  }
})

test('the repository templates group live keys under required and commented knobs under optional', async () => {
  const repoRoot = fileURLToPath(new URL('../../../', import.meta.url))
  const composeRoot = join(repoRoot, 'compose')
  const templates = (await readdir(composeRoot, { recursive: true })).filter(path => path.endsWith('.env.template') && !path.includes('node_modules'))
  expect(templates.length).toBeGreaterThan(5)

  const n8nHeader = /^# (required|optional), (all variants|build, community and enterprise variants|community and enterprise variants|enterprise variant)(, .*)?$/
  const header = /^# (required|optional)\b/
  for (const file of templates) {
    const where = `compose/${file}`
    const lines = (await readFile(join(composeRoot, file), 'utf-8')).split('\n')
    // a template of one kind only (all live or all knobs) needs no header
    if (!lines.some(line => header.test(line))) {
      expect(lines.some(line => /^[A-Z][A-Z0-9_]*=/.test(line)) && lines.some(line => /^# [A-Z][A-Z0-9_]*=/.test(line)), `${where} mixes both kinds without headers`).toBe(false)
      continue
    }
    let section: string | undefined
    for (const line of lines) {
      if (header.test(line)) {
        section = header.exec(line)![1]
        if (file === 'n8n/.env.template')
          expect(line, where).toMatch(n8nHeader)
      }
      else if (/^[A-Z][A-Z0-9_]*=/.test(line)) {
        expect(section, `${line.split('=')[0]} of ${where} is live under a required header`).toBe('required')
      }
      else if (/^# [A-Z][A-Z0-9_]*=/.test(line)) {
        expect(section, `${line.split('=')[0].slice(2)} of ${where} is a knob under an optional header`).toBe('optional')
      }
    }
  }

  // the n8n sections run from the widest scope to the narrowest, required before optional
  const n8n = (await readFile(join(composeRoot, 'n8n/.env.template'), 'utf-8')).split('\n').filter(line => n8nHeader.test(line))
  expect(n8n.map(line => n8nHeader.exec(line)!.slice(1, 3).join(', '))).toEqual([
    'required, all variants',
    'required, build, community and enterprise variants',
    'required, enterprise variant',
    'optional, all variants',
    'optional, build, community and enterprise variants',
    'optional, community and enterprise variants',
    'optional, enterprise variant',
  ])
})

test('secrets read --json prints one array of file, key, value and source in the text order', async () => {
  const dirs = await fixture()
  await fillSecrets(rootDir)
  const n8n = await env(dirs.n8n)
  const vllm = await env(dirs.vllm)

  await secrets(rootDir, ['read'], { json: true })

  expect(logSpy).toHaveBeenCalledOnce()
  expect(JSON.parse(logSpy.mock.calls[0]![0])).toEqual([
    { file: 'compose/models/vllm/.env', key: 'VLLM_API_KEY', value: vllm.VLLM_API_KEY, source: 'generate' },
    { file: 'compose/models/vllm/.env', key: 'HF_TOKEN', value: null, source: 'prompt' },
    { file: 'compose/n8n/.env', key: 'N8N_ENCRYPTION_KEY', value: n8n.N8N_ENCRYPTION_KEY, source: 'generate' },
    { file: 'compose/n8n/.env', key: 'DB_POSTGRESDB_PASSWORD', value: n8n.DB_POSTGRESDB_PASSWORD, source: 'link' },
    { file: 'compose/n8n/.env', key: 'N8N_LICENSE_ACTIVATION_KEY', value: '', source: 'prompt' },
    { file: 'compose/storage/postgres/.env', key: 'POSTGRES_PASSWORD', value: n8n.DB_POSTGRESDB_PASSWORD, source: 'generate' },
  ])
  expect(process.exitCode).toBe(previousExitCode)
})

test('secrets read --json keeps the filter, narrows an exact key to an array and fails like the text form', async () => {
  const dirs = await fixture()
  await fillSecrets(rootDir)
  const vllm = await env(dirs.vllm)

  await secrets(rootDir, ['read', 'vllm_api_key'], { json: true })
  await secrets(rootDir, ['read', 'nothing'], { json: true })

  expect(logSpy).toHaveBeenCalledOnce()
  expect(JSON.parse(logSpy.mock.calls[0]![0])).toEqual([{ file: 'compose/models/vllm/.env', key: 'VLLM_API_KEY', value: vllm.VLLM_API_KEY, source: 'generate' }])
  expect(logErrorMock).toHaveBeenCalledWith(expect.stringContaining('No secret matches "nothing"'))
  expect(process.exitCode).toBe(1)
})
