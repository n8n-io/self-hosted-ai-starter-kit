import { existsSync } from 'node:fs'
import { mkdir, mkdtemp, readdir, readFile, rm, stat, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { stripVTControlCharacters } from 'node:util'
import { compareSync } from 'bcryptjs'
import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import { AI_ENGINES, AI_RUNTIMES, N8N_ASSISTANTS, N8N_VARIANTS } from '../src/schemas/config'
import { BCRYPT_ROUNDS, GENERATOR_TYPES, SECRET_ENCODINGS, SECRET_FILES, SECRET_KEY_PATTERN, SECRET_PREFIX_PATTERN, SECRET_ROTATIONS, SECRET_SOURCES, secretRequiredSchema, secretsManifestSchema } from '../src/schemas/secrets'
import { parseEnvContent } from '../src/utils/env'
import { generateRandom } from '../src/utils/generators'
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

const { checkSecrets, fillSecrets, formatSecretCheck, isUnfilled, listSecrets, readSecretManifests, readSecretState, requiredBy, secrets, setSecret } = await import('../src/commands/secrets')

// three directories: postgres generates the password n8n links to, n8n prompts for the enterprise license,
// vllm generates a prefixed key and has an optional token the template keeps commented out
const POSTGRES_MANIFEST = { secrets: { POSTGRES_PASSWORD: { source: 'generate', rotation: 'manual', description: 'db password' } } }
const N8N_MANIFEST = { secrets: {
  N8N_ENCRYPTION_KEY: { source: 'generate', rotation: 'never', description: 'encryption key' },
  DB_POSTGRESDB_PASSWORD: { source: 'link', from: '../storage/postgres', key: 'POSTGRES_PASSWORD' },
  N8N_LICENSE_ACTIVATION_KEY: { source: 'prompt', description: 'license key', required: { N8N_VARIANT: ['enterprise'] } },
} }
const VLLM_MANIFEST = { secrets: {
  VLLM_API_KEY: { source: 'generate', description: 'api key', generator: { type: 'random', prefix: 'sk-', bytes: 16, encoding: 'base64url' } },
  HF_TOKEN: { source: 'prompt', description: 'hf token' },
} }
const POSTGRES_TEMPLATE = '# postgres\nPOSTGRES_USER=changeUser\nPOSTGRES_PASSWORD=\n'
const N8N_TEMPLATE = 'N8N_VERSION=1\nN8N_LICENSE_ACTIVATION_KEY=\n# secrets\nN8N_ENCRYPTION_KEY=\nDB_POSTGRESDB_USER=changeUser\nDB_POSTGRESDB_PASSWORD=\n'
const VLLM_TEMPLATE = 'VLLM_API_KEY=\n# HF_TOKEN=\n'
// a login: the password is kept beside the .env, the container reads its bcrypt hash, the email is a knob of the template
const OWNER_MANIFEST = { secrets: {
  OWNER_PASSWORD: { source: 'generate', file: '.env.secrets', generator: { type: 'random', bytes: 16, encoding: 'base64url' }, related: ['OWNER_EMAIL'], description: 'owner password' },
  OWNER_PASSWORD_HASH: { source: 'generate', generator: { type: 'bcrypt', input: 'OWNER_PASSWORD', rounds: 4 }, description: 'owner password hash' },
} }
const OWNER_TEMPLATE = '# required\nOWNER_PASSWORD_HASH=\n\n# optional\n# the login\n# OWNER_EMAIL=owner@example.com\n'
const ROOT_ENV = 'DOMAIN=n8n.localhost\nN8N_VARIANT=dev\nAI_RUNTIME=cpu-arm64\nAI_ENGINE=ollama\nAI_MODELS=\n'

const CONFIG = { DOMAIN: 'n8n.localhost', N8N_VARIANT: 'dev', N8N_ASSISTANT: 'false', AI_RUNTIME: 'cpu-arm64', AI_ENGINE: 'ollama', AI_GATEWAY: '', AI_MODELS: '' } as const
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
    postgres: await addDir('compose/storage/postgres', { '.env.template': POSTGRES_TEMPLATE, '.env.json': POSTGRES_MANIFEST, ...(env ? { '.env': POSTGRES_TEMPLATE } : {}) }),
    n8n: await addDir('compose/n8n', { '.env.template': N8N_TEMPLATE, '.env.json': N8N_MANIFEST, ...(env ? { '.env': N8N_TEMPLATE } : {}) }),
    vllm: await addDir('compose/models/vllm', { '.env.template': VLLM_TEMPLATE, '.env.json': VLLM_MANIFEST, ...(env ? { '.env': VLLM_TEMPLATE } : {}) }),
  }
  return dirs
}

async function env(dir: string, file = '.env'): Promise<Record<string, string>> {
  return parseEnvContent(await readFile(join(dir, file), 'utf-8'))
}

/** One directory with the owner login, its .env copied from the template */
async function ownerFixture() {
  await writeFile(join(rootDir, '.env'), ROOT_ENV)
  return addDir('compose/app', { '.env.template': OWNER_TEMPLATE, '.env.json': OWNER_MANIFEST, '.env': OWNER_TEMPLATE })
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
  expect(declared.find(secret => secret.key === 'N8N_ENCRYPTION_KEY')!.entry).toEqual({ source: 'generate', rotation: 'never', description: 'encryption key', file: '.env', generator: { type: 'random', bytes: 32, encoding: 'hex', prefix: '' } })
  expect(declared.find(secret => secret.key === 'VLLM_API_KEY')!.entry).toMatchObject({ rotation: 'free', generator: { type: 'random', prefix: 'sk-', bytes: 16, encoding: 'base64url' } })
})

test.each([
  ['an unknown source', { secrets: { KEY: { source: 'random', description: 'x' } } }],
  ['an unknown field', { secrets: { KEY: { source: 'generate', description: 'x', length: 3 } } }],
  ['a missing description', { secrets: { KEY: { source: 'generate' } } }],
  ['a lower case key', { secrets: { key: { source: 'generate', description: 'x' } } }],
  ['no secrets', { secrets: {} }],
  ['too few bytes', { secrets: { KEY: { source: 'generate', description: 'x', generator: { type: 'random', bytes: 8 } } } }],
  ['a prefix with spaces', { secrets: { KEY: { source: 'generate', description: 'x', generator: { type: 'random', prefix: 'sk ' } } } }],
  ['a generator option on the entry', { secrets: { KEY: { source: 'generate', description: 'x', bytes: 32 } } }],
  ['an unknown generator type', { secrets: { KEY: { source: 'generate', description: 'x', generator: { type: 'uuid' } } } }],
  ['a generator without a type', { secrets: { KEY: { source: 'generate', description: 'x', generator: { bytes: 32 } } } }],
  ['a bcrypt generator without an input', { secrets: { KEY: { source: 'generate', description: 'x', generator: { type: 'bcrypt' } } } }],
  ['too many bcrypt rounds', { secrets: { KEY: { source: 'generate', description: 'x', generator: { type: 'bcrypt', input: 'OTHER', rounds: 16 } } } }],
  ['a random option on a bcrypt generator', { secrets: { KEY: { source: 'generate', description: 'x', generator: { type: 'bcrypt', input: 'OTHER', bytes: 32 } } } }],
  ['an unknown file', { secrets: { KEY: { source: 'generate', description: 'x', file: '.env.local' } } }],
  ['a file on a prompt secret', { secrets: { KEY: { source: 'prompt', description: 'x', file: '.env.secrets' } } }],
  ['an empty related list', { secrets: { KEY: { source: 'generate', description: 'x', related: [] } } }],
  ['a related key in lower case', { secrets: { KEY: { source: 'prompt', description: 'x', related: ['email'] } } }],
  ['a required condition on an unknown root key', { secrets: { KEY: { source: 'prompt', description: 'x', required: { DOMAIN: ['a'] } } } }],
  ['a required condition with an unknown value', { secrets: { KEY: { source: 'prompt', description: 'x', required: { N8N_VARIANT: ['pro'] } } } }],
  ['an empty required condition', { secrets: { KEY: { source: 'prompt', description: 'x', required: {} } } }],
  ['an absolute link', { secrets: { KEY: { source: 'link', from: '/etc', key: 'OTHER' } } }],
  ['a top-level field', { secrets: { KEY: { source: 'generate', description: 'x' } }, extra: true }],
])('the manifest schema rejects %s', (_, manifest) => {
  expect(secretsManifestSchema.safeParse(manifest).success).toBe(false)
})

test('rejects a link to a key no manifest declares', async () => {
  await addDir('compose/n8n', { '.env.template': 'A=\n', '.env.json': { secrets: { A: { source: 'link', from: '../storage/postgres', key: 'B' } } } })

  await expect(readSecretManifests(rootDir)).rejects.toThrow('compose/n8n/.env.json: A links to B of compose/storage/postgres, which no .env.json declares')
})

test('rejects a link to a link', async () => {
  await addDir('compose/a', { '.env.template': 'A=\n', '.env.json': { secrets: { A: { source: 'link', from: '../b', key: 'B' } } } })
  await addDir('compose/b', { '.env.template': 'B=\n', '.env.json': { secrets: { B: { source: 'link', from: '../c', key: 'C' } } } })
  await addDir('compose/c', { '.env.template': 'C=\n', '.env.json': { secrets: { C: { source: 'generate', description: 'c' } } } })

  await expect(readSecretManifests(rootDir)).rejects.toThrow('compose/a/.env.json: A links to B of compose/b, which is a link itself')
})

test.each([
  ['a key the manifest does not declare', {}, 'which the manifest does not declare'],
  ['a prompt secret', { INPUT: { source: 'prompt', description: 'x' } }, 'which is not a random generate entry'],
  ['a link', { INPUT: { source: 'link', from: '../b', key: 'B' } }, 'which is not a random generate entry'],
  ['a derived value', { INPUT: { source: 'generate', description: 'x', generator: { type: 'bcrypt', input: 'OTHER' } }, OTHER: { source: 'generate', description: 'x' } }, 'which is not a random generate entry'],
])('rejects a generator input that is %s', async (_, others, reason) => {
  await addDir('compose/a', { '.env.template': 'HASH=\n', '.env.json': { secrets: { HASH: { source: 'generate', description: 'x', generator: { type: 'bcrypt', input: 'INPUT' } }, ...others } } })
  await addDir('compose/b', { '.env.template': 'B=\n', '.env.json': { secrets: { B: { source: 'generate', description: 'b' } } } })

  await expect(readSecretManifests(rootDir)).rejects.toThrow(`compose/a/.env.json: HASH is derived from INPUT, ${reason}`)
})

test('rejects an invalid manifest naming the file', async () => {
  await addDir('compose/a', { '.env.template': 'A=\n', '.env.json': '{ not json' })

  await expect(readSecretManifests(rootDir)).rejects.toThrow(join(rootDir, 'compose/a/.env.json'))
})

test('rejects a manifest without a template next to it', async () => {
  await addDir('compose/a', { '.env.json': { secrets: { A: { source: 'generate', description: 'a' } } } })

  await expect(readSecretState(rootDir)).rejects.toThrow('No .env.template next to compose/a/.env.json')
})

test('a secret is unfilled while absent, empty or still the template value', () => {
  expect(isUnfilled(undefined, '')).toBe(true)
  expect(isUnfilled('', '')).toBe(true)
  expect(isUnfilled('changePassword', 'changePassword')).toBe(true)
  expect(isUnfilled('abc', '')).toBe(false)
  expect(isUnfilled('abc', undefined)).toBe(false)
})

test('generates random values of the requested shape', () => {
  const hex = generateRandom({ type: 'random', bytes: 32, encoding: 'hex', prefix: '' })
  const prefixed = generateRandom({ type: 'random', bytes: 16, encoding: 'base64url', prefix: 'sk-' })

  expect(hex).toMatch(/^[0-9a-f]{64}$/)
  expect(prefixed).toMatch(/^sk-[A-Za-z0-9_-]{22}$/)
  expect(generateRandom({ type: 'random', bytes: 32, encoding: 'hex', prefix: '' })).not.toBe(hex)
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
    '.env.json': POSTGRES_MANIFEST,
    '.env': 'POSTGRES_PASSWORD=changePassword\n',
  })

  const results = await fillSecrets(rootDir)

  expect(results).toEqual([{ envPath: join(dir, '.env'), key: 'POSTGRES_PASSWORD', status: 'generated' }])
  expect((await env(dir)).POSTGRES_PASSWORD).toMatch(/^[0-9a-f]{64}$/)
})

test('appends a secret key an older .env does not have', async () => {
  const dir = await addDir('compose/storage/postgres', { '.env.template': POSTGRES_TEMPLATE, '.env.json': POSTGRES_MANIFEST, '.env': 'POSTGRES_USER=changeUser\n' })

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

test('a conditional link is filled like every link and missed only while the root .env meets its condition', async () => {
  await writeFile(join(rootDir, '.env'), ROOT_ENV)
  const link = { source: 'link', from: './assistant', key: 'SANDBOX_API_KEYS', required: { N8N_ASSISTANT: ['true'] } }
  // the consumer runs without the key, so its template keeps it commented out
  const template = '# optional\n# N8N_SANDBOX_SERVICE_API_KEY=\n'
  const assistant = await addDir('compose/n8n/assistant', { '.env.template': 'SANDBOX_API_KEYS=\n', '.env.json': { secrets: { SANDBOX_API_KEYS: { source: 'generate', description: 'sandbox key' } } }, '.env': 'SANDBOX_API_KEYS=\n' })
  const n8n = await addDir('compose/n8n', { '.env.template': template, '.env.json': { secrets: { N8N_SANDBOX_SERVICE_API_KEY: link } }, '.env': template })
  const ON = { ...CONFIG, N8N_ASSISTANT: 'true' } as const
  const check = async (config?: typeof CONFIG | typeof ON) => checkSecrets(await readSecretState(rootDir), config).find(check => check.key === 'N8N_SANDBOX_SERVICE_API_KEY')!

  // unfilled: information while the condition is not met or the root config is unknown, a failure once it is
  expect((await check(CONFIG)).status).toBe('unset')
  expect((await check()).status).toBe('unset')
  const missing = await check(ON)
  expect(missing).toMatchObject({ status: 'missing', condition: 'N8N_ASSISTANT=true' })
  expect(formatSecretCheck(rootDir, missing)).toBe('Missing secret N8N_SANDBOX_SERVICE_API_KEY in compose/n8n/.env, required for N8N_ASSISTANT=true')

  // setup fills it whatever the root .env says, appended to the .env since the template has no live key for it
  await fillSecrets(rootDir)
  expect((await env(n8n)).N8N_SANDBOX_SERVICE_API_KEY).toBe((await env(assistant)).SANDBOX_API_KEYS)
  expect((await env(n8n)).N8N_SANDBOX_SERVICE_API_KEY).toMatch(/^[0-9a-f]{64}$/)
  expect((await check(CONFIG)).status).toBe('ok')
  expect((await check(ON)).status).toBe('ok')

  // a link out of step with its source is a mismatch with or without the condition
  await writeFile(join(assistant, '.env'), 'SANDBOX_API_KEYS=changed\n')
  expect((await check(CONFIG)).status).toBe('mismatch')

  // the condition is typed by the root .env lists, and an empty one is refused like that of a prompt
  expect(secretsManifestSchema.safeParse({ secrets: { KEY: link } }).success).toBe(true)
  expect(secretsManifestSchema.safeParse({ secrets: { KEY: { ...link, required: {} } } }).success).toBe(false)
  expect(secretsManifestSchema.safeParse({ secrets: { KEY: { ...link, required: { N8N_ASSISTANT: ['on'] } } } }).success).toBe(false)
})

test('the filter of a manifest directory keeps that directory alone, also when another one is nested in it', async () => {
  await writeFile(join(rootDir, '.env'), ROOT_ENV)
  await addDir('compose/n8n/assistant', { '.env.template': 'SANDBOX_API_KEYS=\n', '.env.json': { secrets: { SANDBOX_API_KEYS: { source: 'generate', description: 'sandbox key' } } }, '.env': 'SANDBOX_API_KEYS=\n' })
  await addDir('compose/n8n', { '.env.template': 'N8N_ENCRYPTION_KEY=\n', '.env.json': { secrets: { N8N_ENCRYPTION_KEY: { source: 'generate', description: 'encryption key' } } }, '.env': 'N8N_ENCRYPTION_KEY=\n' })
  const state = await readSecretState(rootDir)
  const keys = (filter: string) => listSecrets(state, filter).map(secret => secret.key)

  // the filter of the secrets button of a Tilt project
  expect(keys('compose/n8n')).toEqual(['N8N_ENCRYPTION_KEY'])
  expect(keys('compose/n8n/')).toEqual(['N8N_ENCRYPTION_KEY'])
  expect(keys('compose/n8n/assistant')).toEqual(['SANDBOX_API_KEYS'])
  // a part of a directory or key still matches wherever it occurs
  expect(keys('n8n')).toEqual(['N8N_ENCRYPTION_KEY', 'SANDBOX_API_KEYS'])
  expect(keys('compose/n')).toEqual(['N8N_ENCRYPTION_KEY', 'SANDBOX_API_KEYS'])
  expect(keys('sandbox')).toEqual(['SANDBOX_API_KEYS'])
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

test('keeps a password beside the .env and derives the bcrypt hash the container reads', async () => {
  const dir = await ownerFixture()

  const results = await fillSecrets(rootDir)

  expect(results).toEqual([
    { envPath: join(dir, '.env.secrets'), key: 'OWNER_PASSWORD', status: 'generated' },
    { envPath: join(dir, '.env'), key: 'OWNER_PASSWORD_HASH', status: 'generated' },
  ])
  const password = (await env(dir, '.env.secrets')).OWNER_PASSWORD!
  const content = await readFile(join(dir, '.env'), 'utf-8')
  expect(password).toMatch(/^[\w-]{22}$/)
  // single quotes keep docker compose from interpolating the $ of the hash, which has the shape n8n accepts
  expect(content).toMatch(/^OWNER_PASSWORD_HASH='\$2[aby]\$04\$[./A-Za-z0-9]{53}'$/m)
  expect(compareSync(password, (await env(dir)).OWNER_PASSWORD_HASH!)).toBe(true)
  expect((await env(dir)).OWNER_PASSWORD).toBeUndefined()
  expect(await readFile(join(dir, '.env.secrets'), 'utf-8')).toMatch(/^# secrets no container reads.*\nOWNER_PASSWORD=/)
  expect((await stat(join(dir, '.env.secrets'))).mode & 0o077).toBe(0)

  // the hash still fits its input, so a second run leaves its salt alone
  expect(await fillSecrets(rootDir)).toEqual([])
  expect(await readFile(join(dir, '.env'), 'utf-8')).toBe(content)
})

test('a derived value follows its input: a stale hash is a mismatch that the next fill repairs', async () => {
  const dir = await ownerFixture()
  await fillSecrets(rootDir)
  await writeFile(join(dir, '.env.secrets'), 'OWNER_PASSWORD=byhand\n')

  const stale = checkSecrets(await readSecretState(rootDir), CONFIG).find(check => check.key === 'OWNER_PASSWORD_HASH')!
  expect(stale).toEqual({ envPath: join(dir, '.env'), key: 'OWNER_PASSWORD_HASH', status: 'mismatch', source: { envPath: join(dir, '.env.secrets'), key: 'OWNER_PASSWORD' }, derived: true })
  expect(formatSecretCheck(rootDir, stale)).toBe('OWNER_PASSWORD_HASH in compose/app/.env does not match OWNER_PASSWORD in compose/app/.env.secrets')

  expect(await fillSecrets(rootDir)).toEqual([{ envPath: join(dir, '.env'), key: 'OWNER_PASSWORD_HASH', status: 'generated' }])
  expect(compareSync('byhand', (await env(dir)).OWNER_PASSWORD_HASH!)).toBe(true)
  expect(checkSecrets(await readSecretState(rootDir), CONFIG).map(check => `${check.key} ${check.status}`)).toEqual(['OWNER_PASSWORD ok', 'OWNER_PASSWORD_HASH ok'])
})

test('a deleted .env.secrets is a missing secret, and the next fill makes a new password with its hash', async () => {
  const dir = await ownerFixture()
  await fillSecrets(rootDir)
  const before = (await env(dir)).OWNER_PASSWORD_HASH
  await rm(join(dir, '.env.secrets'))

  const checks = checkSecrets(await readSecretState(rootDir), CONFIG)
  expect(checks.map(check => `${check.key} ${check.status}`)).toEqual(['OWNER_PASSWORD missing', 'OWNER_PASSWORD_HASH ok'])
  expect(formatSecretCheck(rootDir, checks[0]!)).toBe('Missing secret OWNER_PASSWORD in compose/app/.env.secrets')

  expect((await fillSecrets(rootDir)).map(result => result.key)).toEqual(['OWNER_PASSWORD', 'OWNER_PASSWORD_HASH'])
  expect((await env(dir)).OWNER_PASSWORD_HASH).not.toBe(before)
  expect(compareSync((await env(dir, '.env.secrets')).OWNER_PASSWORD!, (await env(dir)).OWNER_PASSWORD_HASH!)).toBe(true)
})

test('secrets set writes a password of your own and derives its hash, once', async () => {
  const dir = await ownerFixture()
  await fillSecrets(rootDir)

  await secrets(rootDir, ['set', 'OWNER_PASSWORD', 'my pa$$word #1'])

  expect(logSuccessMock.mock.calls.map(call => call[0])).toEqual([
    'OWNER_PASSWORD set in compose/app/.env.secrets',
    'OWNER_PASSWORD_HASH derived in compose/app/.env',
  ])
  expect((await env(dir, '.env.secrets')).OWNER_PASSWORD).toBe('my pa$$word #1')
  expect(compareSync('my pa$$word #1', (await env(dir)).OWNER_PASSWORD_HASH!)).toBe(true)
  const content = await readFile(join(dir, '.env'), 'utf-8')

  // the same password again leaves the hash and its salt alone
  logSuccessMock.mockReset()
  await secrets(rootDir, ['set', 'OWNER_PASSWORD', 'my pa$$word #1'])
  expect(logSuccessMock.mock.calls.map(call => call[0])).toEqual(['OWNER_PASSWORD set in compose/app/.env.secrets'])
  expect(await readFile(join(dir, '.env'), 'utf-8')).toBe(content)
  expect(process.exitCode).toBe(previousExitCode)
})

test.each([
  [['set', 'OWNER_PASSWORD_HASH', 'x'], 'OWNER_PASSWORD_HASH is derived from OWNER_PASSWORD in compose/app/.env.secrets, run `pnpm run secrets set OWNER_PASSWORD`'],
  [['set', 'OWNER_PASSWORD', 'it\'s'], 'Invalid OWNER_PASSWORD: the value must not hold a single quote, a backslash or a line break'],
  [['set', 'OWNER_PASSWORD', 'back\\slash'], 'Invalid OWNER_PASSWORD: the value must not hold a single quote, a backslash or a line break'],
  [['set'], 'Missing secret key. Expected one of: OWNER_PASSWORD'],
])('secrets %j exits with code 1 and leaves a derived value and its input alone', async (argv, message) => {
  const dir = await ownerFixture()
  await fillSecrets(rootDir)
  const before = [await readFile(join(dir, '.env'), 'utf-8'), await readFile(join(dir, '.env.secrets'), 'utf-8')]

  await secrets(rootDir, argv)

  expect(logErrorMock).toHaveBeenCalledWith(message)
  expect([await readFile(join(dir, '.env'), 'utf-8'), await readFile(join(dir, '.env.secrets'), 'utf-8')]).toEqual(before)
  expect(process.exitCode).toBe(1)
})

test('secrets read prints a secret with its related keys under the file that holds it and hides derived values', async () => {
  const dir = await ownerFixture()
  await fillSecrets(rootDir)
  const password = (await env(dir, '.env.secrets')).OWNER_PASSWORD!
  const hash = (await env(dir)).OWNER_PASSWORD_HASH!

  await secrets(rootDir, ['read'])
  await secrets(rootDir, ['read', 'app'], { json: true })
  // an exact key prints the bare value, the related keys stay out of a pipe; a derived value is there when named
  await secrets(rootDir, ['read', 'owner_password'])
  await secrets(rootDir, ['read', 'owner_password_hash'])
  // what the .env sets wins over the default the template shows commented out
  await writeFile(join(dir, '.env'), `${await readFile(join(dir, '.env'), 'utf-8')}OWNER_EMAIL=me@example.com\n`)
  await secrets(rootDir, ['read', 'app'])

  const printed = logSpy.mock.calls.map((call: unknown[]) => stripVTControlCharacters(call[0] as string))
  expect(printed[0]).toBe(`compose/app/.env.secrets\nOWNER_EMAIL=owner@example.com\nOWNER_PASSWORD=${password}`)
  expect(JSON.parse(printed[1]!)).toEqual([
    { file: 'compose/app/.env.secrets', key: 'OWNER_PASSWORD', value: password, source: 'generate', related: { OWNER_EMAIL: 'owner@example.com' } },
  ])
  expect(printed.slice(2, 4)).toEqual([password, hash])
  expect(printed[4]).toBe(`compose/app/.env.secrets\nOWNER_EMAIL=me@example.com\nOWNER_PASSWORD=${password}`)
  expect(process.exitCode).toBe(previousExitCode)
})

test('secrets read points at setup when a .env.secrets is missing', async () => {
  await ownerFixture()

  await secrets(rootDir, ['read'])

  expect(logErrorMock).toHaveBeenCalledWith('No compose/app/.env.secrets file found. Run `pnpm run setup` first.')
  expect(logSpy).not.toHaveBeenCalled()
  expect(process.exitCode).toBe(1)
})

test('the repository manifests match their templates, their compose files and the editor schema', async () => {
  const repoRoot = fileURLToPath(new URL('../../../', import.meta.url))
  const state = await readSecretState(repoRoot)

  expect([...state.directories.keys()].map(dir => relative(repoRoot, dir))).toEqual([
    'compose/models/litellm',
    'compose/models/vllm',
    'compose/n8n',
    'compose/n8n/assistant',
    'compose/storage/pgadmin',
    'compose/storage/postgres',
  ])

  for (const secret of state.declared) {
    const directory = state.directories.get(secret.dir)!
    const where = `${secret.key} of ${relative(repoRoot, secret.dir)}`
    const template = await readFile(join(secret.dir, '.env.template'), 'utf-8')
    const composeFiles = (await readdir(secret.dir)).filter(name => /^docker-compose.*\.yml$/.test(name))
    const compose = (await Promise.all(composeFiles.map(name => readFile(join(secret.dir, name), 'utf-8')))).join('\n')
    if (secret.entry.source === 'generate' && secret.entry.file === '.env.secrets') {
      // a secret no container reads is in neither the template nor a compose file (the colon keeps a key apart from one it prefixes)
      expect(directory.template[secret.key], where).toBeUndefined()
      expect(directory.defaults[secret.key], where).toBeUndefined()
      expect(compose, where).not.toContain(`\${${secret.key}:`)
    } else if (secret.entry.source === 'prompt' ? secret.entry.required === undefined : secret.entry.source === 'link' && secret.entry.required !== undefined) {
      // optional human secrets, and the links only a root .env condition needs, stay commented out in the template
      // and optional in the compose file: the service runs without them
      expect(directory.template[secret.key], where).toBeUndefined()
      expect(template, where).toContain(`# ${secret.key}=`)
      expect(compose, where).toContain(`\${${secret.key}:-`)
    } else {
      // everything setup fills or verify requires is live and empty, and the compose file refuses to start without it
      expect(directory.template[secret.key], where).toBe('')
      expect(compose, where).toContain(`\${${secret.key}:?}`)
    }
    // a related key is a key of the same template: live with a value, or a knob whose commented default is the one of the compose file
    for (const related of secret.entry.source === 'link' ? [] : secret.entry.related ?? []) {
      if (directory.template[related] === undefined)
        expect(compose, `${related} related to ${where}`).toContain(`\${${related}:-${directory.defaults[related]}}`)
      else
        expect(directory.template[related], `${related} related to ${where}`).not.toBe('')
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
  const schema = JSON.parse(await readFile(join(composeRoot, '.env.schema.json'), 'utf-8'))
  expect(schema.properties.secrets.propertyNames.pattern).toBe(SECRET_KEY_PATTERN.source)
  expect(schema.$defs.link.properties.key.pattern).toBe(SECRET_KEY_PATTERN.source)
  expect(schema.$defs.entry.oneOf.map((ref: { $ref: string }) => ref.$ref.split('/').pop())).toEqual([...SECRET_SOURCES])
  expect(schema.$defs.generate.properties.rotation.enum).toEqual([...SECRET_ROTATIONS])
  expect(schema.$defs.generate.properties.file.enum).toEqual([...SECRET_FILES])
  expect(schema.$defs.generator.oneOf.map((ref: { $ref: string }) => ref.$ref.split('/').pop())).toEqual([...GENERATOR_TYPES])
  expect(schema.$defs.random.properties.encoding.enum).toEqual([...SECRET_ENCODINGS])
  expect(schema.$defs.random.properties.prefix.pattern).toBe(SECRET_PREFIX_PATTERN.source)
  expect(schema.$defs.bcrypt.properties.input.pattern).toBe(SECRET_KEY_PATTERN.source)
  expect(schema.$defs.bcrypt.properties.rounds).toEqual({ type: 'integer', minimum: BCRYPT_ROUNDS.min, maximum: BCRYPT_ROUNDS.max, default: BCRYPT_ROUNDS.default })
  expect(schema.$defs.related.items.pattern).toBe(SECRET_KEY_PATTERN.source)
  // a prompt and a link share the condition, with the values of the root .env lists
  expect(schema.$defs.prompt.properties.required).toEqual({ $ref: '#/$defs/required' })
  expect(schema.$defs.link.properties.required).toEqual({ $ref: '#/$defs/required' })
  expect(schema.$defs.required.properties.N8N_VARIANT.items.enum).toEqual([...N8N_VARIANTS])
  expect(schema.$defs.required.properties.N8N_ASSISTANT.items.enum).toEqual([...N8N_ASSISTANTS])
  expect(schema.$defs.required.properties.AI_ENGINE.items.enum).toEqual([...AI_ENGINES])
  expect(schema.$defs.required.properties.AI_RUNTIME.items.enum).toEqual([...AI_RUNTIMES])
  expect(Object.keys(schema.$defs.required.properties)).toEqual(Object.keys(secretRequiredSchema.shape))
  for (const dir of state.directories.keys()) {
    const manifest = JSON.parse(await readFile(join(dir, '.env.json'), 'utf-8'))
    expect(resolve(dir, manifest.$schema), relative(repoRoot, dir)).toBe(join(composeRoot, '.env.schema.json'))
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
