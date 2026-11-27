import type { DockerRunner } from '../src/utils/docker'
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import { verify } from '../src/commands/verify'
import { setLogLevel } from '../src/utils/logger'

// Unlike the other command tests this one keeps the real clack output and
// captures stdout, to prove what actually reaches the terminal (or the Tilt log).

let rootDir: string
let writeSpy: ReturnType<typeof vi.spyOn>
let previousExitCode: typeof process.exitCode

beforeEach(async () => {
  rootDir = await mkdtemp(join(tmpdir(), 'n8n-starter-quiet-'))
  previousExitCode = process.exitCode
  writeSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true)
})

afterEach(async () => {
  writeSpy.mockRestore()
  setLogLevel('info')
  process.exitCode = previousExitCode
  await rm(rootDir, { recursive: true, force: true })
})

function stdout(): string {
  return writeSpy.mock.calls.map((call: unknown[]) => String(call[0])).join('')
}

async function addTemplate(dir: string, withEnv: boolean) {
  const fullDir = join(rootDir, dir)
  await mkdir(fullDir, { recursive: true })
  await writeFile(join(fullDir, '.env.template'), 'KEY=value\n')
  if (withEnv)
    await writeFile(join(fullDir, '.env'), 'KEY=value\n')
}

/** The networks for `network ls`, versions above the minimums for the `version` probes */
function fakeDocker(networks: string[]): DockerRunner {
  return async args => args[0] === 'network' ? networks.map(name => `${name}\n`).join('') : '99.0.0\n'
}

test('verify writes nothing to stdout at the error level when the environment is complete', async () => {
  await addTemplate('compose/n8n', true)
  setLogLevel('error')

  await verify(rootDir, { run: fakeDocker(['n8n-starter-public', 'n8n-starter-private']) })

  expect(stdout()).toBe('')
})

test('verify writes only the failed checks at the error level', async () => {
  await addTemplate('compose/n8n', false)
  await addTemplate('compose/postgres', true)
  setLogLevel('error')

  await verify(rootDir, { run: fakeDocker(['n8n-starter-public']) })

  const output = stdout()
  expect(output).toContain('Missing compose/n8n/.env')
  expect(output).toContain('Missing docker network n8n-starter-private')
  expect(output).toContain('Run `pnpm run setup` to create the missing files, secrets and networks.')
  expect(output).not.toContain('Found')
  expect(output).not.toContain('n8n-starter verify')
})

test('verify writes the full report at the default level', async () => {
  await addTemplate('compose/n8n', true)

  await verify(rootDir, { run: fakeDocker(['n8n-starter-public', 'n8n-starter-private']) })

  const output = stdout()
  expect(output).toContain('n8n-starter verify')
  expect(output).toContain('Found compose/n8n/.env')
  expect(output).toContain('Found docker network n8n-starter-public')
  expect(output).toContain('Environment verified.')
})
