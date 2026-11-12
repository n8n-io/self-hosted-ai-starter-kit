import type { DockerRunner } from '../src/utils/docker'
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import * as clack from '@clack/prompts'
import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import { formatVerifyResult, verify, verifyDockerNetworks, verifyEnvFiles, verifyEnvironment } from '../src/commands/verify'
import { HINT_SYMBOL, setLogLevel } from '../src/utils/logger'
import { DOCKER_INFO_FORMAT } from '../src/utils/platform'

// Silence the clack output so the command can run end-to-end in tests
vi.mock('@clack/prompts', () => ({
  intro: vi.fn(),
  outro: vi.fn(),
  log: { success: vi.fn(), info: vi.fn(), warn: vi.fn(), error: vi.fn(), message: vi.fn() },
}))

let rootDir: string
let previousExitCode: typeof process.exitCode

beforeEach(async () => {
  rootDir = await mkdtemp(join(tmpdir(), 'n8n-starter-verify-'))
  previousExitCode = process.exitCode
  vi.clearAllMocks()
})

afterEach(async () => {
  await rm(rootDir, { recursive: true, force: true })
  process.exitCode = previousExitCode
  setLogLevel('info')
})

async function addTemplate(dir: string, withEnv: boolean, content = 'KEY=value\n') {
  const fullDir = join(rootDir, dir)
  await mkdir(fullDir, { recursive: true })
  await writeFile(join(fullDir, '.env.template'), content)
  if (withEnv)
    await writeFile(join(fullDir, '.env'), content)
  return fullDir
}

const ROOT_ENV = 'DOMAIN=n8n.localhost\nN8N_VARIANT=dev\nAI_RUNTIME=cpu-arm64\nAI_ENGINE=ollama\nAI_MODELS=\n'

/** postgres generates the password n8n links to; n8n prompts for the enterprise license */
async function addSecrets(variant = 'dev') {
  await writeFile(join(rootDir, '.env'), ROOT_ENV.replace('N8N_VARIANT=dev', `N8N_VARIANT=${variant}`))
  const postgres = await addTemplate('compose/storage/postgres', true, 'POSTGRES_PASSWORD=\n')
  await writeFile(join(postgres, '.env.secrets.json'), JSON.stringify({ secrets: { POSTGRES_PASSWORD: { source: 'generate', description: 'db' } } }))
  const n8n = await addTemplate('compose/n8n', true, 'N8N_LICENSE_ACTIVATION_KEY=\nDB_POSTGRESDB_PASSWORD=\n')
  await writeFile(join(n8n, '.env.secrets.json'), JSON.stringify({ secrets: {
    DB_POSTGRESDB_PASSWORD: { source: 'link', from: '../storage/postgres', key: 'POSTGRES_PASSWORD' },
    N8N_LICENSE_ACTIVATION_KEY: { source: 'prompt', description: 'license', required: { N8N_VARIANT: ['enterprise'] } },
  } }))
  return { postgres, n8n }
}

/** An arm64 Docker Desktop with 16 GB, or the same machine with the nvidia runtime registered */
const INFO_LINE = 'aarch64|17179869184|8|Docker Desktop|io.containerd.runc.v2,runc,\n'
const NVIDIA_LINE = 'x86_64|67353571328|16|Ubuntu 24.04.1 LTS|io.containerd.runc.v2,nvidia,runc,\n'

/** Networks by name plus the daemon and compose versions (above the minimums unless overridden) and the platform line */
function fakeDocker(networks: string[], { docker = '29.8.2', compose = '5.5.0', info = INFO_LINE } = {}): DockerRunner {
  return async (args) => {
    if (args[0] === 'network' && args[1] === 'ls')
      return networks.map(name => `${name}\n`).join('')
    if (args[0] === 'version')
      return `${docker}\n`
    if (args[0] === 'compose' && args[1] === 'version')
      return `${compose}\n`
    if (args[0] === 'info' && args[1] === '--format' && args[2] === DOCKER_INFO_FORMAT)
      return info
    throw new Error(`Unexpected docker call: ${args.join(' ')}`)
  }
}

/** Fixed host values so the platform line does not depend on the machine running the tests */
const HOST = { arch: 'arm64', os: 'linux' as const, totalmem: 32 * 1024 ** 3, exists: async () => false }
const DETECTED_LINE = 'Detected docker aarch64, 8 cpus, 16 GB memory (Docker Desktop), host linux/arm64 32 GB, no gpu'

const NODE = process.version.slice(1)
const REQUIREMENT_LINES = [`Found node ${NODE} (24.0.0 or newer required)`, 'Found docker 29.8.2 (25.0.0 or newer required)', 'Found docker compose 5.5.0 (2.24.0 or newer required)']

const failingDocker: DockerRunner = async () => {
  throw new Error('Cannot connect to the Docker daemon')
}

test('reports which .env.template files have a generated .env next to them', async () => {
  await addTemplate('compose/n8n', true)
  await addTemplate('compose/storage/postgres', false)

  const checks = await verifyEnvFiles(rootDir)

  expect(checks).toEqual([
    { templatePath: join(rootDir, 'compose/n8n/.env.template'), envPath: join(rootDir, 'compose/n8n/.env'), exists: true },
    { templatePath: join(rootDir, 'compose/storage/postgres/.env.template'), envPath: join(rootDir, 'compose/storage/postgres/.env'), exists: false },
  ])
})

test('reports which docker networks exist by exact name', async () => {
  const run = fakeDocker(['bridge', 'n8n', 'n8n-starter-public'])

  const checks = await verifyDockerNetworks(['n8n-starter-public', 'n8n-starter-private'], { run, ...HOST })

  expect(checks).toEqual([
    { name: 'n8n-starter-public', exists: true },
    { name: 'n8n-starter-private', exists: false },
  ])
})

test('passes when every .env file and both networks exist', async () => {
  await addTemplate('.', true)
  await addTemplate('compose/n8n', true)
  const run = fakeDocker(['bridge', 'n8n-starter-public', 'n8n-starter-private'])

  const result = await verifyEnvironment(rootDir, { run, ...HOST })

  expect(result.ok).toBe(true)
  expect(result.dockerError).toBeUndefined()
  expect(result.networks.every(n => n.exists)).toBe(true)
})

test('fails when a .env file is missing', async () => {
  await addTemplate('compose/n8n', false)
  const run = fakeDocker(['n8n-starter-public', 'n8n-starter-private'])

  const result = await verifyEnvironment(rootDir, { run, ...HOST })

  expect(result.ok).toBe(false)
  expect(result.envFiles).toEqual([expect.objectContaining({ exists: false })])
})

test('fails when a docker network is missing', async () => {
  await addTemplate('compose/n8n', true)
  const run = fakeDocker(['n8n-starter-public'])

  const result = await verifyEnvironment(rootDir, { run, ...HOST })

  expect(result.ok).toBe(false)
  expect(result.networks).toEqual([
    { name: 'n8n-starter-public', exists: true },
    { name: 'n8n-starter-private', exists: false },
  ])
})

test('fails when docker cannot be queried', async () => {
  await addTemplate('compose/n8n', true)

  const result = await verifyEnvironment(rootDir, { run: failingDocker, ...HOST })

  expect(result.ok).toBe(false)
  expect(result.dockerError).toBe('Cannot connect to the Docker daemon')
  expect(result.networks).toEqual([])
  expect(result.requirements.map(check => check.ok)).toEqual([true, false, false])
})

test('fails when docker is older than the minimum', async () => {
  await addTemplate('compose/n8n', true)
  const run = fakeDocker(['n8n-starter-public', 'n8n-starter-private'], { docker: '24.0.7' })

  const result = await verifyEnvironment(rootDir, { run, ...HOST })

  expect(result.ok).toBe(false)
  expect(result.requirements.find(check => check.name === 'docker')).toEqual({ name: 'docker', minimum: '25.0.0', installed: '24.0.7', ok: false })
  expect(result.dockerError).toBeUndefined()
})

test('fails when node is older than the minimum', async () => {
  await addTemplate('compose/n8n', true)
  const run = fakeDocker(['n8n-starter-public', 'n8n-starter-private'])

  const result = await verifyEnvironment(rootDir, { run, nodeVersion: 'v22.1.0', ...HOST })

  expect(result.ok).toBe(false)
  expect(result.requirements[0]).toEqual({ name: 'node', minimum: '24.0.0', installed: '22.1.0', ok: false })
})

test('passes with no templates when the networks exist', async () => {
  const run = fakeDocker(['n8n-starter-public', 'n8n-starter-private'])

  const result = await verifyEnvironment(rootDir, { run, ...HOST })

  expect(result.ok).toBe(true)
  expect(result.envFiles).toEqual([])
})

test('verify command exits with code 0 when the environment is complete', async () => {
  await addTemplate('compose/n8n', true)
  const run = fakeDocker(['n8n-starter-public', 'n8n-starter-private'])

  const ok = await verify(rootDir, { run, ...HOST })

  expect(ok).toBe(true)
  expect(process.exitCode).toBe(previousExitCode)
})

test('verify command exits with code 1 when something is missing', async () => {
  await addTemplate('compose/n8n', false)
  const run = fakeDocker(['n8n-starter-public', 'n8n-starter-private'])

  const ok = await verify(rootDir, { run, ...HOST })

  expect(ok).toBe(false)
  expect(process.exitCode).toBe(1)
})

test('verify logs nothing at the error level when the environment is complete', async () => {
  await addTemplate('compose/n8n', true)
  const run = fakeDocker(['n8n-starter-public', 'n8n-starter-private'])
  setLogLevel('error')

  const ok = await verify(rootDir, { run, ...HOST })

  expect(ok).toBe(true)
  expect(clack.intro).not.toHaveBeenCalled()
  expect(clack.outro).not.toHaveBeenCalled()
  expect(clack.log.success).not.toHaveBeenCalled()
  expect(clack.log.info).not.toHaveBeenCalled()
  expect(clack.log.warn).not.toHaveBeenCalled()
  expect(clack.log.error).not.toHaveBeenCalled()
  expect(clack.log.message).not.toHaveBeenCalled()
})

test('verify logs only the failed checks at the error level', async () => {
  await addTemplate('compose/n8n', false)
  await addTemplate('compose/postgres', true)
  const run = fakeDocker(['n8n-starter-public'], { compose: '2.23.3' })
  setLogLevel('error')

  const ok = await verify(rootDir, { run, ...HOST })

  expect(ok).toBe(false)
  expect(vi.mocked(clack.log.error).mock.calls.map(call => call[0])).toEqual([
    'docker compose 2.23.3 is older than the required 2.24.0',
    'Missing compose/n8n/.env',
    'Missing docker network n8n-starter-private',
  ])
  expect(vi.mocked(clack.log.message).mock.calls).toEqual([
    ['Run `pnpm run setup` to create the missing files, secrets and networks.', { symbol: HINT_SYMBOL }],
    ['Install the versions listed under Prerequisites in README.md.', { symbol: HINT_SYMBOL }],
  ])
  expect(clack.intro).not.toHaveBeenCalled()
  expect(clack.outro).not.toHaveBeenCalled()
  expect(clack.log.success).not.toHaveBeenCalled()
})

test('fails on an unfilled generated secret and on a link that differs from its source', async () => {
  const { postgres, n8n } = await addSecrets()
  const run = fakeDocker(['n8n-starter-public', 'n8n-starter-private'])

  const unfilled = await verifyEnvironment(rootDir, { run, ...HOST })
  await writeFile(join(postgres, '.env'), 'POSTGRES_PASSWORD=abc\n')
  await writeFile(join(n8n, '.env'), 'N8N_LICENSE_ACTIVATION_KEY=\nDB_POSTGRESDB_PASSWORD=old\n')
  const stale = await verifyEnvironment(rootDir, { run, ...HOST })
  await writeFile(join(n8n, '.env'), 'N8N_LICENSE_ACTIVATION_KEY=\nDB_POSTGRESDB_PASSWORD=abc\n')
  const synced = await verifyEnvironment(rootDir, { run, ...HOST })

  expect(unfilled.ok).toBe(false)
  expect(unfilled.secrets.map(check => `${check.key} ${check.status}`)).toEqual(['DB_POSTGRESDB_PASSWORD missing', 'N8N_LICENSE_ACTIVATION_KEY unset', 'POSTGRES_PASSWORD missing'])
  expect(stale.ok).toBe(false)
  expect(stale.secrets.map(check => `${check.key} ${check.status}`)).toEqual(['DB_POSTGRESDB_PASSWORD mismatch', 'N8N_LICENSE_ACTIVATION_KEY unset', 'POSTGRES_PASSWORD ok'])
  expect(synced.ok).toBe(true)
})

test('fails on a human secret the current root .env requires', async () => {
  const { postgres, n8n } = await addSecrets('enterprise')
  await writeFile(join(postgres, '.env'), 'POSTGRES_PASSWORD=abc\n')
  await writeFile(join(n8n, '.env'), 'N8N_LICENSE_ACTIVATION_KEY=\nDB_POSTGRESDB_PASSWORD=abc\n')
  const run = fakeDocker(['n8n-starter-public', 'n8n-starter-private'])

  const result = await verifyEnvironment(rootDir, { run, ...HOST })

  expect(result.ok).toBe(false)
  expect(result.secrets.find(check => check.key === 'N8N_LICENSE_ACTIVATION_KEY')).toMatchObject({ status: 'required', condition: 'N8N_VARIANT=enterprise' })
})

test('fails on an invalid manifest naming the file', async () => {
  const dir = await addTemplate('compose/n8n', true)
  await writeFile(join(dir, '.env.secrets.json'), JSON.stringify({ secrets: { KEY: { source: 'nope' } } }))
  const run = fakeDocker(['n8n-starter-public', 'n8n-starter-private'])

  const result = await verifyEnvironment(rootDir, { run, ...HOST })

  expect(result.ok).toBe(false)
  expect(result.secretsError).toContain(join(dir, '.env.secrets.json'))
})

test('verify logs only the failed secret checks at the error level', async () => {
  const { postgres, n8n } = await addSecrets('enterprise')
  await writeFile(join(postgres, '.env'), 'POSTGRES_PASSWORD=abc\n')
  await writeFile(join(n8n, '.env'), 'N8N_LICENSE_ACTIVATION_KEY=\nDB_POSTGRESDB_PASSWORD=old\n')
  const run = fakeDocker(['n8n-starter-public', 'n8n-starter-private'])
  setLogLevel('error')

  const ok = await verify(rootDir, { run, ...HOST })

  expect(ok).toBe(false)
  expect(vi.mocked(clack.log.error).mock.calls.map(call => call[0])).toEqual([
    'DB_POSTGRESDB_PASSWORD in compose/n8n/.env differs from POSTGRES_PASSWORD in compose/storage/postgres/.env',
    'N8N_LICENSE_ACTIVATION_KEY in compose/n8n/.env is required for N8N_VARIANT=enterprise, run `pnpm run secrets set N8N_LICENSE_ACTIVATION_KEY`',
  ])
  expect(vi.mocked(clack.log.message).mock.calls).toEqual([
    ['Run `pnpm run setup` to create the missing files, secrets and networks.', { symbol: HINT_SYMBOL }],
  ])
  expect(clack.log.success).not.toHaveBeenCalled()
  expect(clack.log.info).not.toHaveBeenCalled()
})

test('the report buckets the lines by level and hints at setup only for what setup fixes', async () => {
  const { postgres, n8n } = await addSecrets('enterprise')
  await writeFile(join(postgres, '.env'), 'POSTGRES_PASSWORD=abc\n')
  await writeFile(join(n8n, '.env'), 'N8N_LICENSE_ACTIVATION_KEY=\nDB_POSTGRESDB_PASSWORD=abc\n')
  const run = fakeDocker(['n8n-starter-public', 'n8n-starter-private'])

  const requiredOnly = formatVerifyResult(rootDir, await verifyEnvironment(rootDir, { run, ...HOST }))
  const dockerDown = formatVerifyResult(rootDir, await verifyEnvironment(rootDir, { run: failingDocker, ...HOST }))
  const noCompose: DockerRunner = async (args) => {
    if (args[0] === 'compose')
      throw new Error('docker: \'compose\' is not a docker command.\nSee \'docker --help\'')
    return run(args)
  }
  const composeMissing = formatVerifyResult(rootDir, await verifyEnvironment(rootDir, { run: noCompose, ...HOST }))
  await addTemplate('compose/services/qdrant', false)
  const missingFile = formatVerifyResult(rootDir, await verifyEnvironment(rootDir, { run, ...HOST }))

  expect(requiredOnly).toEqual({
    ok: false,
    success: [...REQUIREMENT_LINES, 'Found compose/n8n/.env', 'Found compose/storage/postgres/.env', 'Secret DB_POSTGRESDB_PASSWORD set in compose/n8n/.env', 'Secret POSTGRES_PASSWORD set in compose/storage/postgres/.env', 'Found docker network n8n-starter-public', 'Found docker network n8n-starter-private'],
    info: [DETECTED_LINE],
    warnings: [],
    errors: ['N8N_LICENSE_ACTIVATION_KEY in compose/n8n/.env is required for N8N_VARIANT=enterprise, run `pnpm run secrets set N8N_LICENSE_ACTIVATION_KEY`'],
    hints: [],
  })
  expect(missingFile.errors).toContain('Missing compose/services/qdrant/.env')
  expect(missingFile.hints).toEqual(['Run `pnpm run setup` to create the missing files, secrets and networks.'])
  expect(dockerDown.errors).toContain('Could not list the docker networks. Is Docker installed and running?')
  // no platform line without a daemon to ask
  expect(dockerDown.info).toEqual([])
  expect(dockerDown.warnings).toEqual([])
  expect(dockerDown.errors).toContain('docker not found: Cannot connect to the Docker daemon (25.0.0 or newer required)')
  expect(dockerDown.hints).toEqual(['Install the versions listed under Prerequisites in README.md.'])
  expect(composeMissing.ok).toBe(false)
  expect(composeMissing.errors).toEqual(['docker compose not found: docker: \'compose\' is not a docker command. (2.24.0 or newer required)', 'N8N_LICENSE_ACTIVATION_KEY in compose/n8n/.env is required for N8N_VARIANT=enterprise, run `pnpm run secrets set N8N_LICENSE_ACTIVATION_KEY`'])
  expect(composeMissing.hints).toEqual(['Install the versions listed under Prerequisites in README.md.'])
})

test('the report warns when no template exists', async () => {
  const report = formatVerifyResult(rootDir, await verifyEnvironment(rootDir, { run: fakeDocker(['n8n-starter-public', 'n8n-starter-private']), ...HOST }))

  expect(report.ok).toBe(true)
  expect(report.warnings).toEqual([`No .env.template files found in ${rootDir}`])
})

test('verify --json prints the report once and logs nothing', async () => {
  await addTemplate('compose/n8n', false)
  const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {})
  setLogLevel('info')

  const ok = await verify(rootDir, { run: fakeDocker(['n8n-starter-public']), ...HOST }, { json: true })

  expect(ok).toBe(false)
  expect(process.exitCode).toBe(1)
  expect(logSpy).toHaveBeenCalledOnce()
  expect(JSON.parse(logSpy.mock.calls[0]![0])).toEqual({
    ok: false,
    success: [...REQUIREMENT_LINES, 'Found docker network n8n-starter-public'],
    info: [DETECTED_LINE],
    warnings: [],
    errors: ['Missing compose/n8n/.env', 'Missing docker network n8n-starter-private'],
    hints: ['Run `pnpm run setup` to create the missing files, secrets and networks.'],
  })
  expect(clack.intro).not.toHaveBeenCalled()
  expect(clack.outro).not.toHaveBeenCalled()
  expect(clack.log.error).not.toHaveBeenCalled()
  logSpy.mockRestore()
})

test('verify --json keeps the exit code when the environment is complete', async () => {
  await addTemplate('compose/n8n', true)
  const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {})

  const ok = await verify(rootDir, { run: fakeDocker(['n8n-starter-public', 'n8n-starter-private']), ...HOST }, { json: true })

  expect(ok).toBe(true)
  expect(process.exitCode).toBe(previousExitCode)
  expect(JSON.parse(logSpy.mock.calls[0]![0])).toMatchObject({ ok: true, errors: [], hints: [] })
  logSpy.mockRestore()
})

test('warns when AI_RUNTIME is not the runtime of the detected platform, without failing', async () => {
  await addTemplate('.', true, ROOT_ENV.replace('AI_RUNTIME=cpu-arm64', 'AI_RUNTIME=cpu-x86-64'))
  const run = fakeDocker(['n8n-starter-public', 'n8n-starter-private'])

  const result = await verifyEnvironment(rootDir, { run, ...HOST })
  const report = formatVerifyResult(rootDir, result)

  expect(result.ok).toBe(true)
  expect(result.platform).toMatchObject({ arch: 'arm64', runtime: 'cpu-arm64', memory: 16 })
  expect(report.info).toEqual([DETECTED_LINE])
  expect(report.warnings).toEqual(['AI_RUNTIME=cpu-x86-64 does not match the detected platform (docker aarch64, 8 cpus, 16 GB memory (Docker Desktop), host linux/arm64 32 GB, no gpu), run `pnpm run config AI_RUNTIME cpu-arm64`'])
  expect(report.hints).toEqual([])
})

test('does not warn when AI_RUNTIME matches the platform, and suggests the gpu runtime of an nvidia daemon', async () => {
  await addTemplate('.', true, ROOT_ENV)
  const matching = await verifyEnvironment(rootDir, { run: fakeDocker(['n8n-starter-public', 'n8n-starter-private']), ...HOST })
  const nvidia = await verifyEnvironment(rootDir, { run: fakeDocker(['n8n-starter-public', 'n8n-starter-private'], { info: NVIDIA_LINE }), ...HOST, arch: 'x64' })

  expect(matching.runtimeWarning).toBeUndefined()
  expect(nvidia.platform).toMatchObject({ gpu: 'nvidia', runtime: 'gpu-nvidia', memory: 63 })
  expect(nvidia.runtimeWarning).toContain('run `pnpm run config AI_RUNTIME gpu-nvidia`')
  expect(nvidia.ok).toBe(true)
})

test('verify logs the mismatch at the warn level and stays silent about the platform at the error level', async () => {
  await addTemplate('.', true, ROOT_ENV.replace('AI_RUNTIME=cpu-arm64', 'AI_RUNTIME=gpu-amd'))
  const run = fakeDocker(['n8n-starter-public', 'n8n-starter-private'])

  setLogLevel('warn')
  await verify(rootDir, { run, ...HOST })
  expect(vi.mocked(clack.log.warn).mock.calls.map(call => call[0])).toEqual([expect.stringContaining('AI_RUNTIME=gpu-amd does not match the detected platform')])
  expect(clack.log.info).not.toHaveBeenCalled()

  vi.clearAllMocks()
  setLogLevel('error')
  const ok = await verify(rootDir, { run, ...HOST })
  expect(ok).toBe(true)
  expect(clack.log.warn).not.toHaveBeenCalled()
  expect(clack.log.info).not.toHaveBeenCalled()
})
