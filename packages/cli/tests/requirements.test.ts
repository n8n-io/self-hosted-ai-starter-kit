import type { DockerRunner } from '../src/utils/docker'
import { readFile } from 'node:fs/promises'
import { expect, test } from 'vitest'
import { checkComposeVersion, checkDockerVersion, checkNodeVersion, checkRequirements, parseVersion, REQUIREMENTS, satisfiesMinimum } from '../src/utils/requirements'

test('parses the first major.minor.patch of a version string', () => {
  expect(parseVersion('v24.15.0')).toEqual([24, 15, 0])
  expect(parseVersion('29.8.2\n')).toEqual([29, 8, 2])
  expect(parseVersion('27.0.3-desktop.1')).toEqual([27, 0, 3])
  expect(parseVersion('Docker Compose version v2.24.0')).toEqual([2, 24, 0])
  expect(parseVersion('5.5')).toEqual([5, 5, 0])
  expect(parseVersion('unknown')).toBeUndefined()
})

test('compares versions numerically against a minimum', () => {
  expect(satisfiesMinimum([24, 0, 0], [24, 0, 0])).toBe(true)
  expect(satisfiesMinimum([24, 15, 0], [24, 0, 0])).toBe(true)
  expect(satisfiesMinimum([25, 0, 0], [24, 15, 0])).toBe(true)
  expect(satisfiesMinimum([23, 99, 99], [24, 0, 0])).toBe(false)
  expect(satisfiesMinimum([2, 23, 9], [2, 24, 0])).toBe(false)
  expect(satisfiesMinimum([2, 24, 1], [2, 24, 0])).toBe(true)
})

test('checks the node version against the minimum', () => {
  expect(checkNodeVersion('v24.15.0')).toEqual({ name: 'node', minimum: REQUIREMENTS.node, installed: '24.15.0', ok: true })
  expect(checkNodeVersion('v22.1.0')).toEqual({ name: 'node', minimum: REQUIREMENTS.node, installed: '22.1.0', ok: false })
  expect(checkNodeVersion(process.version).ok).toBe(true)
})

test('queries the docker daemon and the compose plugin versions', async () => {
  const calls: string[][] = []
  const run: DockerRunner = async (args) => {
    calls.push(args)
    return args[0] === 'compose' ? '5.5.0\n' : '29.8.2\n'
  }

  expect(await checkDockerVersion({ run })).toEqual({ name: 'docker', minimum: REQUIREMENTS.docker, installed: '29.8.2', ok: true })
  expect(await checkComposeVersion({ run })).toEqual({ name: 'docker compose', minimum: REQUIREMENTS.compose, installed: '5.5.0', ok: true })
  expect(calls).toEqual([
    ['version', '--format', '{{.Server.Version}}'],
    ['compose', 'version', '--short'],
  ])
})

test('fails a tool that is too old or cannot be queried without throwing', async () => {
  const old: DockerRunner = async args => args[0] === 'compose' ? 'v2.23.3\n' : '24.0.7\n'
  const missing: DockerRunner = async (args) => {
    throw new Error(`docker: '${args[0]}' is not a docker command.\nSee 'docker --help'`)
  }

  expect(await checkDockerVersion({ run: old })).toMatchObject({ installed: '24.0.7', ok: false })
  expect(await checkComposeVersion({ run: old })).toMatchObject({ installed: '2.23.3', ok: false })
  expect(await checkComposeVersion({ run: missing })).toEqual({ name: 'docker compose', minimum: REQUIREMENTS.compose, ok: false, error: 'docker: \'compose\' is not a docker command.' })
  expect(await checkDockerVersion({ run: async () => 'garbage' })).toMatchObject({ ok: false, error: 'unrecognised version "garbage"' })
})

test('checks node, docker and docker compose in that order', async () => {
  const run: DockerRunner = async args => args[0] === 'compose' ? '2.24.0' : '25.0.0'

  const checks = await checkRequirements({ run, nodeVersion: 'v24.0.0' })

  expect(checks.map(check => `${check.name} ${check.ok}`)).toEqual(['node true', 'docker true', 'docker compose true'])
})

test('the root package.json engines.node mirrors the node requirement', async () => {
  const pkg = JSON.parse(await readFile(new URL('../../../package.json', import.meta.url), 'utf-8'))

  expect(pkg.engines.node).toBe(`>=${parseVersion(REQUIREMENTS.node)![0]}`)
})
