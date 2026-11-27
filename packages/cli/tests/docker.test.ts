import type { DockerRunner } from '../src/utils/docker'
import { expect, test } from 'vitest'
import { createDockerNetwork, dockerNetworkExists, ensureDockerNetworks, listDockerNetworks } from '../src/utils/docker'

/**
 * A stand-in for the docker CLI that keeps its networks in memory, so the
 * tests never need a Docker daemon.
 */
function fakeDocker(networks: string[] = []) {
  const calls: string[][] = []
  const run: DockerRunner = async (args) => {
    calls.push(args)
    const [resource, action] = args
    if (resource === 'network' && action === 'ls')
      return networks.map(name => `${name}\n`).join('')
    if (resource === 'network' && action === 'create') {
      networks.push(args.at(-1)!)
      return 'f1e2d3c4b5a6\n'
    }
    throw new Error(`Unexpected docker call: ${args.join(' ')}`)
  }
  return { run, calls, networks }
}

test('lists docker network names, ignoring blank lines', async () => {
  const run: DockerRunner = async () => 'bridge\nhost\n\nn8n-starter-public\n'

  expect(await listDockerNetworks({ run })).toEqual(['bridge', 'host', 'n8n-starter-public'])
})

test('checks for a network by exact name', async () => {
  const { run } = fakeDocker(['bridge', 'n8n'])

  expect(await dockerNetworkExists('n8n', { run })).toBe(true)
  expect(await dockerNetworkExists('n8n-starter-public', { run })).toBe(false)
})

test('creates a bridge network by default', async () => {
  const { run, calls } = fakeDocker()

  await createDockerNetwork('n8n-starter-public', { run })

  expect(calls).toEqual([['network', 'create', '--driver', 'bridge', 'n8n-starter-public']])
})

test('creates a network with a custom driver', async () => {
  const { run, calls } = fakeDocker()

  await createDockerNetwork('n8n-overlay', { driver: 'overlay', run })

  expect(calls).toEqual([['network', 'create', '--driver', 'overlay', 'n8n-overlay']])
})

test('ensures networks by creating only the missing ones', async () => {
  const { run, calls, networks } = fakeDocker(['bridge', 'n8n-starter-private'])

  const results = await ensureDockerNetworks(['n8n-starter-public', 'n8n-starter-private'], { run })

  expect(results).toEqual([
    { name: 'n8n-starter-public', status: 'created' },
    { name: 'n8n-starter-private', status: 'exists' },
  ])
  expect(calls).toEqual([
    ['network', 'ls', '--format', '{{.Name}}'],
    ['network', 'create', '--driver', 'bridge', 'n8n-starter-public'],
  ])
  expect(networks).toContain('n8n-starter-public')
})

test('ensuring networks is idempotent across runs', async () => {
  const { run } = fakeDocker()

  const first = await ensureDockerNetworks(['n8n-starter-public', 'n8n-starter-private'], { run })
  const second = await ensureDockerNetworks(['n8n-starter-public', 'n8n-starter-private'], { run })

  expect(first.map(r => r.status)).toEqual(['created', 'created'])
  expect(second.map(r => r.status)).toEqual(['exists', 'exists'])
})

test('propagates docker errors', async () => {
  const run: DockerRunner = async () => {
    throw new Error('Cannot connect to the Docker daemon')
  }

  await expect(ensureDockerNetworks(['n8n-starter-public'], { run })).rejects.toThrow('Cannot connect to the Docker daemon')
})
