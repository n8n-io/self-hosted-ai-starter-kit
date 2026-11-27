import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import { logger } from './logger'

const execFileAsync = promisify(execFile)

/** Runs the docker CLI with the given arguments and resolves with its stdout. */
export type DockerRunner = (args: string[]) => Promise<string>

export const runDocker: DockerRunner = async (args) => {
  logger.debug(`docker ${args.join(' ')}`)
  const { stdout } = await execFileAsync('docker', args)
  return stdout
}

export interface DockerOptions {
  run?: DockerRunner
}

export interface CreateDockerNetworkOptions extends DockerOptions {
  driver?: string
}

export interface DockerNetworkResult {
  name: string
  status: 'created' | 'exists'
}

export async function listDockerNetworks({ run = runDocker }: DockerOptions = {}): Promise<string[]> {
  const stdout = await run(['network', 'ls', '--format', '{{.Name}}'])
  return stdout
    .split('\n')
    .map(line => line.trim())
    .filter(line => line.length > 0)
}

export async function dockerNetworkExists(name: string, options: DockerOptions = {}): Promise<boolean> {
  const networks = await listDockerNetworks(options)
  return networks.includes(name)
}

export async function createDockerNetwork(name: string, { driver = 'bridge', run = runDocker }: CreateDockerNetworkOptions = {}): Promise<void> {
  await run(['network', 'create', '--driver', driver, name])
}

/**
 * Creates every network in `names` that does not exist yet. Existing networks
 * are left untouched, so this is safe to run repeatedly.
 */
export async function ensureDockerNetworks(names: string[], options: CreateDockerNetworkOptions = {}): Promise<DockerNetworkResult[]> {
  const existing = await listDockerNetworks(options)
  const results: DockerNetworkResult[] = []

  for (const name of names) {
    if (existing.includes(name)) {
      results.push({ name, status: 'exists' })
      continue
    }
    await createDockerNetwork(name, options)
    results.push({ name, status: 'created' })
  }

  return results
}
