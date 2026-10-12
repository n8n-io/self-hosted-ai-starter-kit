import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, expect, test } from 'vitest'
import { findEnvTemplates, generateEnvFiles } from '../src/commands/setup'

let rootDir: string

beforeEach(async () => {
  rootDir = await mkdtemp(join(tmpdir(), 'n8n-starter-setup-'))
})

afterEach(async () => {
  await rm(rootDir, { recursive: true, force: true })
})

async function addTemplate(dir: string, content = 'KEY=value\n') {
  const fullDir = join(rootDir, dir)
  await mkdir(fullDir, { recursive: true })
  await writeFile(join(fullDir, '.env.template'), content)
  return fullDir
}

test('finds .env.template files recursively', async () => {
  await addTemplate('.')
  await addTemplate('compose/n8n')
  await addTemplate('compose/n8n-data/postgres')

  const templates = await findEnvTemplates(rootDir)

  expect(templates.sort()).toEqual([
    join(rootDir, '.env.template'),
    join(rootDir, 'compose/n8n/.env.template'),
    join(rootDir, 'compose/n8n-data/postgres/.env.template'),
  ].sort())
})

test('ignores node_modules, dist and hidden directories', async () => {
  await addTemplate('node_modules/some-pkg')
  await addTemplate('dist')
  await addTemplate('.archive')
  await addTemplate('compose')

  const templates = await findEnvTemplates(rootDir)

  expect(templates).toEqual([join(rootDir, 'compose/.env.template')])
})

test('generates a .env file next to each template', async () => {
  await addTemplate('compose/n8n', 'N8N_VERSION=1.0.0\n')
  await addTemplate('compose/postgres', 'POSTGRES_USER=changeUser\n')

  const results = await generateEnvFiles(rootDir)

  expect(results).toHaveLength(2)
  expect(results.every(r => r.status === 'created')).toBe(true)
  expect(await readFile(join(rootDir, 'compose/n8n/.env'), 'utf-8')).toBe('N8N_VERSION=1.0.0\n')
  expect(await readFile(join(rootDir, 'compose/postgres/.env'), 'utf-8')).toBe('POSTGRES_USER=changeUser\n')
})

test('does not overwrite an existing .env file', async () => {
  const dir = await addTemplate('compose/n8n', 'KEY=template\n')
  await writeFile(join(dir, '.env'), 'KEY=user-edited\n')

  const results = await generateEnvFiles(rootDir)

  expect(results).toEqual([
    expect.objectContaining({ status: 'skipped' }),
  ])
  expect(await readFile(join(dir, '.env'), 'utf-8')).toBe('KEY=user-edited\n')
})

test('returns no results when there are no templates', async () => {
  const results = await generateEnvFiles(rootDir)
  expect(results).toEqual([])
})

test('is idempotent across runs', async () => {
  await addTemplate('compose/n8n')

  const first = await generateEnvFiles(rootDir)
  const second = await generateEnvFiles(rootDir)

  expect(first.map(r => r.status)).toEqual(['created'])
  expect(second.map(r => r.status)).toEqual(['skipped'])
})
