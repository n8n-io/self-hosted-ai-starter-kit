import type { DockerRunner } from '../src/utils/docker'
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import * as clack from '@clack/prompts'
import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import { DOCKER_NETWORKS, findEnvTemplates, generateEnvFiles, setup } from '../src/commands/setup'
import { parseEnvContent } from '../src/utils/env'

// Silence the clack output so the command can run end-to-end in tests
vi.mock('@clack/prompts', () => ({
  intro: vi.fn(),
  outro: vi.fn(),
  log: { success: vi.fn(), info: vi.fn(), warn: vi.fn(), error: vi.fn(), message: vi.fn() },
}))

const ROOT_TEMPLATE = '# The hardware supported ai runtime\nAI_RUNTIME=cpu-arm64\nAI_ENGINE=ollama\nAI_MODELS=\nN8N_VARIANT=dev\nDOMAIN=n8n.localhost\n'
const X86_LINE = 'x86_64|33566629888|12|Docker Desktop|io.containerd.runc.v2,runc,\n'
/** Fixed host values so the detection does not depend on the machine running the tests */
const HOST = { arch: 'x64', os: 'linux' as const, totalmem: 64 * 1024 ** 3, exists: async () => false }

/** Both networks present, the daemon an x86 one unless `info` says otherwise */
function fakeDocker({ networks = ['n8n-starter-public', 'n8n-starter-private'], info = X86_LINE } = {}): DockerRunner {
  return async (args) => {
    if (args[1] === 'ls')
      return networks.map(name => `${name}\n`).join('')
    if (args[0] === 'info')
      return info
    throw new Error(`Unexpected docker call: ${args.join(' ')}`)
  }
}

let rootDir: string

beforeEach(async () => {
  rootDir = await mkdtemp(join(tmpdir(), 'n8n-starter-setup-'))
  vi.clearAllMocks()
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
  await addTemplate('compose/storage/postgres')

  const templates = await findEnvTemplates(rootDir)

  expect(templates.sort()).toEqual([
    join(rootDir, '.env.template'),
    join(rootDir, 'compose/n8n/.env.template'),
    join(rootDir, 'compose/storage/postgres/.env.template'),
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

test('setup creates the n8n docker networks that are missing', async () => {
  await addTemplate('compose/n8n')
  const created: string[] = []
  const run: DockerRunner = async (args) => {
    if (args[1] === 'ls')
      return 'bridge\nn8n-starter-private\n'
    if (args[1] === 'create') {
      created.push(args.at(-1)!)
      return 'f1e2d3c4b5a6\n'
    }
    throw new Error(`Unexpected docker call: ${args.join(' ')}`)
  }

  await setup(rootDir, { run, ...HOST })

  expect(DOCKER_NETWORKS).toEqual(['n8n-starter-public', 'n8n-starter-private'])
  expect(created).toEqual(['n8n-starter-public'])
  expect(await readFile(join(rootDir, 'compose/n8n/.env'), 'utf-8')).toBe('KEY=value\n')
})

test('setup fails with a non-zero exit code when docker is unavailable', async () => {
  const previousExitCode = process.exitCode
  const run: DockerRunner = async () => {
    throw new Error('Cannot connect to the Docker daemon')
  }

  await setup(rootDir, { run, ...HOST })

  expect(process.exitCode).toBe(1)
  process.exitCode = previousExitCode
})

test('setup fills the secrets of the .env files once and copies the links', async () => {
  const postgres = await addTemplate('compose/storage/postgres', 'POSTGRES_USER=changeUser\nPOSTGRES_PASSWORD=\n')
  await writeFile(join(postgres, '.env.secrets.json'), JSON.stringify({ secrets: { POSTGRES_PASSWORD: { source: 'generate', description: 'db' } } }))
  const n8n = await addTemplate('compose/n8n', 'N8N_VERSION=1\nDB_POSTGRESDB_PASSWORD=\n')
  await writeFile(join(n8n, '.env.secrets.json'), JSON.stringify({ secrets: { DB_POSTGRESDB_PASSWORD: { source: 'link', from: '../storage/postgres', key: 'POSTGRES_PASSWORD' } } }))
  const run = fakeDocker()

  await setup(rootDir, { run, ...HOST })
  const first = await readFile(join(n8n, '.env'), 'utf-8')
  await setup(rootDir, { run, ...HOST })

  expect(await readFile(join(postgres, '.env'), 'utf-8')).toMatch(/^POSTGRES_USER=changeUser\nPOSTGRES_PASSWORD=[0-9a-f]{64}\n$/)
  expect(first).toBe(`N8N_VERSION=1\nDB_POSTGRESDB_PASSWORD=${(await readFile(join(postgres, '.env'), 'utf-8')).match(/PASSWORD=(.*)/)![1]}\n`)
  expect(await readFile(join(n8n, '.env'), 'utf-8')).toBe(first)
})

test('setup writes the detected runtime into the root .env it created', async () => {
  await addTemplate('.', ROOT_TEMPLATE)
  await addTemplate('compose/n8n')

  await setup(rootDir, { run: fakeDocker(), ...HOST })

  const root = await readFile(join(rootDir, '.env'), 'utf-8')
  expect(parseEnvContent(root)).toEqual({ AI_RUNTIME: 'cpu-x86-64', AI_ENGINE: 'ollama', AI_MODELS: '', N8N_VARIANT: 'dev', DOMAIN: 'n8n.localhost' })
  // the comment stays, the template is untouched
  expect(root).toContain('# The hardware supported ai runtime')
  expect(await readFile(join(rootDir, '.env.template'), 'utf-8')).toBe(ROOT_TEMPLATE)
  expect(await readFile(join(rootDir, 'compose/n8n/.env'), 'utf-8')).toBe('KEY=value\n')
  expect(clack.log.info).toHaveBeenCalledWith('Detected docker x86_64, 12 cpus, 31 GB memory (Docker Desktop), host linux/x64 64 GB, no gpu')
  expect(clack.log.success).toHaveBeenCalledWith('AI_RUNTIME=cpu-x86-64 (detected)')
  expect(clack.log.warn).not.toHaveBeenCalled()
})

test('setup leaves an existing root .env alone and warns when its runtime does not fit the platform', async () => {
  await addTemplate('.', ROOT_TEMPLATE)
  const existing = ROOT_TEMPLATE.replace('AI_RUNTIME=cpu-arm64', 'AI_RUNTIME=gpu-amd')
  await writeFile(join(rootDir, '.env'), existing)

  await setup(rootDir, { run: fakeDocker(), ...HOST })

  expect(await readFile(join(rootDir, '.env'), 'utf-8')).toBe(existing)
  expect(clack.log.warn).toHaveBeenCalledWith(expect.stringContaining('AI_RUNTIME=gpu-amd does not match the detected platform'))
  expect(clack.log.warn).toHaveBeenCalledWith(expect.stringContaining('run `pnpm run config AI_RUNTIME cpu-x86-64`'))
  expect(clack.log.success).not.toHaveBeenCalledWith(expect.stringContaining('AI_RUNTIME'))
})

test('setup keeps the template runtime when it already fits, and picks a gpu runtime from the nvidia docker runtime', async () => {
  await addTemplate('.', ROOT_TEMPLATE)
  const arm = 'aarch64|17179869184|8|Docker Desktop|io.containerd.runc.v2,runc,\n'
  await setup(rootDir, { run: fakeDocker({ info: arm }), ...HOST, arch: 'arm64' })
  expect(parseEnvContent(await readFile(join(rootDir, '.env'), 'utf-8')).AI_RUNTIME).toBe('cpu-arm64')
  expect(clack.log.success).not.toHaveBeenCalledWith(expect.stringContaining('AI_RUNTIME'))
  expect(clack.log.warn).not.toHaveBeenCalled()

  await rm(join(rootDir, '.env'))
  const nvidia = 'x86_64|67353571328|16|Ubuntu|io.containerd.runc.v2,nvidia,runc,\n'
  await setup(rootDir, { run: fakeDocker({ info: nvidia }), ...HOST })
  expect(parseEnvContent(await readFile(join(rootDir, '.env'), 'utf-8')).AI_RUNTIME).toBe('gpu-nvidia')
  expect(clack.log.success).toHaveBeenCalledWith('AI_RUNTIME=gpu-nvidia (detected)')
})

test('setup falls back to the host architecture for a new root .env when docker is down', async () => {
  await addTemplate('.', ROOT_TEMPLATE)
  const run: DockerRunner = async () => {
    throw new Error('Cannot connect to the Docker daemon')
  }
  const previousExitCode = process.exitCode

  await setup(rootDir, { run, ...HOST })

  expect(parseEnvContent(await readFile(join(rootDir, '.env'), 'utf-8')).AI_RUNTIME).toBe('cpu-x86-64')
  expect(clack.log.info).toHaveBeenCalledWith('Detected no docker info, host linux/x64 64 GB, no gpu')
  // the networks still fail the run
  expect(process.exitCode).toBe(1)
  process.exitCode = previousExitCode
})

test('setup does not detect the platform without a root template and never touches a root .env without AI_RUNTIME', async () => {
  await addTemplate('compose/n8n')
  const calls: string[][] = []
  const run: DockerRunner = async (args) => {
    calls.push(args)
    return args[1] === 'ls' ? 'n8n-starter-public\nn8n-starter-private\n' : X86_LINE
  }

  await setup(rootDir, { run, ...HOST })
  expect(calls.map(args => args[0])).toEqual(['network'])

  await addTemplate('.', 'KEY=value\n')
  await setup(rootDir, { run, ...HOST })
  expect(await readFile(join(rootDir, '.env'), 'utf-8')).toBe('KEY=value\n')
  expect(calls.map(args => args[0])).toEqual(['network', 'info', 'network'])
})
