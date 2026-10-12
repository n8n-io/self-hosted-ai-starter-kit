import { existsSync } from 'node:fs'
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import { configSchema, domainSchema } from '../src/schemas/config'
import { parseEnvContent, updateEnvContent } from '../src/utils/env'

const { textMock, selectMock, CANCEL } = vi.hoisted(() => ({
  textMock: vi.fn(),
  selectMock: vi.fn(),
  CANCEL: Symbol('clack-cancel'),
}))

vi.mock('@clack/prompts', () => ({
  intro: vi.fn(),
  outro: vi.fn(),
  cancel: vi.fn(),
  text: textMock,
  select: selectMock,
  isCancel: (value: unknown) => value === CANCEL,
  log: { info: vi.fn(), warn: vi.fn(), success: vi.fn() },
}))

const { config } = await import('../src/commands/config')

const ENV_CONTENT = `# The domain to run the docker compose services
DOMAIN=dev.localhost
# The hardware supported ai runtime
# Options: cpu-x86-64, cpu-arm64, gpu-nvidia or gpu-amd
AI_RUNTIME=cpu-x86-64
# Which variant of n8n to run in ./compose/n8n
# Options: base, community or enterprise
N8N_VARIANT=base
`

let rootDir: string

beforeEach(async () => {
  rootDir = await mkdtemp(join(tmpdir(), 'n8n-starter-config-'))
  textMock.mockReset()
  selectMock.mockReset()
})

afterEach(async () => {
  await rm(rootDir, { recursive: true, force: true })
  process.exitCode = 0
})

test('config schema accepts the template defaults and rejects invalid values', () => {
  expect(configSchema.safeParse({
    DOMAIN: 'dev.localhost',
    AI_RUNTIME: 'cpu-x86-64',
    N8N_VARIANT: 'base',
  }).success).toBe(true)

  expect(configSchema.safeParse({
    DOMAIN: 'dev.localhost',
    AI_RUNTIME: 'gpu-intel',
    N8N_VARIANT: 'base',
  }).success).toBe(false)

  expect(configSchema.safeParse({
    DOMAIN: 'dev.localhost',
    AI_RUNTIME: 'cpu-arm64',
    N8N_VARIANT: 'pro',
  }).success).toBe(false)
})

test('domain schema rejects invalid hostnames', () => {
  expect(domainSchema.safeParse('dev.localhost').success).toBe(true)
  expect(domainSchema.safeParse('').success).toBe(false)
  expect(domainSchema.safeParse('not a domain').success).toBe(false)
  expect(domainSchema.safeParse('-bad.localhost').success).toBe(false)
})

test('parseEnvContent reads keys and ignores comments', () => {
  expect(parseEnvContent(ENV_CONTENT)).toEqual({
    DOMAIN: 'dev.localhost',
    AI_RUNTIME: 'cpu-x86-64',
    N8N_VARIANT: 'base',
  })
})

test('updateEnvContent replaces values while preserving comments and appends missing keys', () => {
  const updated = updateEnvContent(ENV_CONTENT, {
    AI_RUNTIME: 'gpu-nvidia',
    NEW_KEY: 'value',
  })

  expect(updated).toContain('# Options: cpu-x86-64, cpu-arm64, gpu-nvidia or gpu-amd')
  expect(updated).toContain('AI_RUNTIME=gpu-nvidia')
  expect(updated).toContain('DOMAIN=dev.localhost')
  expect(updated.endsWith('NEW_KEY=value\n')).toBe(true)
})

test('config writes the selected options to the root .env file', async () => {
  const envPath = join(rootDir, '.env')
  await writeFile(envPath, ENV_CONTENT)
  textMock.mockResolvedValue('my.localhost')
  selectMock.mockResolvedValueOnce('gpu-nvidia').mockResolvedValueOnce('community')

  await config(rootDir)

  const updated = await readFile(envPath, 'utf-8')
  expect(parseEnvContent(updated)).toEqual({
    DOMAIN: 'my.localhost',
    AI_RUNTIME: 'gpu-nvidia',
    N8N_VARIANT: 'community',
  })
  expect(updated).toContain('# Options: base, community or enterprise')
})

test('config leaves the .env file untouched when a prompt is cancelled', async () => {
  const envPath = join(rootDir, '.env')
  await writeFile(envPath, ENV_CONTENT)
  textMock.mockResolvedValue('my.localhost')
  selectMock.mockResolvedValue(CANCEL)

  await config(rootDir)

  expect(await readFile(envPath, 'utf-8')).toBe(ENV_CONTENT)
})

test('config fails without writing when no .env file exists', async () => {
  textMock.mockResolvedValue('my.localhost')

  await config(rootDir)

  expect(textMock).not.toHaveBeenCalled()
  expect(existsSync(join(rootDir, '.env'))).toBe(false)
  expect(process.exitCode).toBe(1)
})
