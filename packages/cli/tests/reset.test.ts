import { existsSync } from 'node:fs'
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import * as clack from '@clack/prompts'
import { afterEach, beforeEach, expect, test, vi } from 'vitest'

const { confirmMock, CANCEL } = vi.hoisted(() => ({
  confirmMock: vi.fn(),
  CANCEL: Symbol('clack-cancel'),
}))

vi.mock('@clack/prompts', () => ({
  intro: vi.fn(),
  outro: vi.fn(),
  cancel: vi.fn(),
  confirm: confirmMock,
  isCancel: (value: unknown) => value === CANCEL,
  log: { info: vi.fn(), warn: vi.fn(), success: vi.fn(), error: vi.fn(), step: vi.fn(), message: vi.fn() },
}))

const { findEnvFiles, reset } = await import('../src/commands/reset')

let rootDir: string

beforeEach(async () => {
  rootDir = await mkdtemp(join(tmpdir(), 'n8n-starter-reset-'))
  confirmMock.mockReset()
})

afterEach(async () => {
  await rm(rootDir, { recursive: true, force: true })
})

async function addEnvFile(dir: string, name = '.env') {
  const fullDir = join(rootDir, dir)
  await mkdir(fullDir, { recursive: true })
  const path = join(fullDir, name)
  await writeFile(path, 'KEY=value\n')
  return path
}

test('finds .env files recursively, ignoring templates and ignored directories', async () => {
  const kept = await addEnvFile('compose/n8n')
  await addEnvFile('compose/n8n', '.env.template')
  await addEnvFile('node_modules/some-pkg')
  await addEnvFile('.archive')

  const envFiles = await findEnvFiles(rootDir)

  expect(envFiles).toEqual([kept])
})

test('deletes all .env files when confirmed', async () => {
  const first = await addEnvFile('compose/n8n')
  const second = await addEnvFile('compose/postgres')
  const template = await addEnvFile('compose/n8n', '.env.template')
  confirmMock.mockResolvedValue(true)

  await reset(rootDir)

  expect(existsSync(first)).toBe(false)
  expect(existsSync(second)).toBe(false)
  expect(existsSync(template)).toBe(true)
})

test('keeps all files when the confirmation is declined', async () => {
  const envFile = await addEnvFile('compose/n8n')
  confirmMock.mockResolvedValue(false)

  await reset(rootDir)

  expect(existsSync(envFile)).toBe(true)
})

test('keeps all files when the prompt is cancelled', async () => {
  const envFile = await addEnvFile('compose/n8n')
  confirmMock.mockResolvedValue(CANCEL)

  await reset(rootDir)

  expect(existsSync(envFile)).toBe(true)
})

test('does not prompt when there are no .env files', async () => {
  await reset(rootDir)

  expect(confirmMock).not.toHaveBeenCalled()
})

test('warns about the generated secrets the data in .volumes/ depends on before asking', async () => {
  const dir = join(rootDir, 'compose/n8n')
  await mkdir(dir, { recursive: true })
  await writeFile(join(dir, '.env.template'), 'N8N_ENCRYPTION_KEY=\nN8N_USER_MANAGEMENT_JWT_SECRET=\n')
  await writeFile(join(dir, '.env'), 'N8N_ENCRYPTION_KEY=abc\nN8N_USER_MANAGEMENT_JWT_SECRET=def\n')
  await writeFile(join(dir, '.env.secrets.json'), JSON.stringify({ secrets: {
    N8N_ENCRYPTION_KEY: { source: 'generate', rotation: 'never', description: 'enc' },
    N8N_USER_MANAGEMENT_JWT_SECRET: { source: 'generate', description: 'jwt' },
  } }))
  confirmMock.mockResolvedValue(false)

  await reset(rootDir)

  expect(clack.log.warn).toHaveBeenCalledWith('The data in .volumes/ needs N8N_ENCRYPTION_KEY (compose/n8n/.env): back them up with `pnpm run secrets read` first')
  expect(confirmMock).toHaveBeenCalled()
})
