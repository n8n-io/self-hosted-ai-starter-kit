import { existsSync } from 'node:fs'
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
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
  log: { info: vi.fn(), warn: vi.fn(), success: vi.fn() },
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
