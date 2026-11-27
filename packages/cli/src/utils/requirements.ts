import type { DockerOptions } from './docker'
import { runDocker } from './docker'

/**
 * The minimum tool versions this repository runs on, checked by `verify` (see ../../../../SPEC.md). Mirrored by
 * the Prerequisites of ../../../../README.md and `engines.node` of the root package.json.
 */
export const REQUIREMENTS = {
  node: '24.0.0',
  docker: '25.0.0',
  compose: '2.24.0',
} as const

export type RequirementName = 'node' | 'docker' | 'docker compose'

export interface RequirementCheck {
  name: RequirementName
  minimum: string
  /** The version found, as `major.minor.patch`; absent when the tool could not be queried */
  installed?: string
  ok: boolean
  /** The first line of the error when the tool could not be queried */
  error?: string
}

export interface RequirementOptions extends DockerOptions {
  /** The node version to check instead of the running one (tests) */
  nodeVersion?: string
}

export type Version = [major: number, minor: number, patch: number]

/** The first `major.minor[.patch]` of a version string (`v24.15.0`, `27.0.3-desktop.1`, `Docker Compose version v2.24.0`) */
export function parseVersion(text: string): Version | undefined {
  const match = text.match(/(\d+)\.(\d+)(?:\.(\d+))?/)
  if (match === null)
    return undefined
  return [Number(match[1]), Number(match[2]), Number(match[3] ?? 0)]
}

export function formatVersion(version: Version): string {
  return version.join('.')
}

export function satisfiesMinimum(installed: Version, minimum: Version): boolean {
  for (let index = 0; index < 3; index++) {
    if (installed[index]! !== minimum[index]!)
      return installed[index]! > minimum[index]!
  }
  return true
}

function check(name: RequirementName, minimum: string, text: string): RequirementCheck {
  const installed = parseVersion(text)
  if (installed === undefined)
    return { name, minimum, ok: false, error: `unrecognised version "${text.trim()}"` }
  return { name, minimum, installed: formatVersion(installed), ok: satisfiesMinimum(installed, parseVersion(minimum)!) }
}

function failed(name: RequirementName, minimum: string, error: unknown): RequirementCheck {
  const message = (error as Error).message ?? String(error)
  return { name, minimum, ok: false, error: message.split('\n')[0]!.trim() }
}

export function checkNodeVersion(version: string = process.version): RequirementCheck {
  return check('node', REQUIREMENTS.node, version)
}

/** The daemon version, since the compose features in use (`healthcheck.start_interval`) depend on the engine */
export async function checkDockerVersion({ run = runDocker }: DockerOptions = {}): Promise<RequirementCheck> {
  try {
    return check('docker', REQUIREMENTS.docker, await run(['version', '--format', '{{.Server.Version}}']))
  } catch (error) {
    return failed('docker', REQUIREMENTS.docker, error)
  }
}

export async function checkComposeVersion({ run = runDocker }: DockerOptions = {}): Promise<RequirementCheck> {
  try {
    return check('docker compose', REQUIREMENTS.compose, await run(['compose', 'version', '--short']))
  } catch (error) {
    return failed('docker compose', REQUIREMENTS.compose, error)
  }
}

/** Every requirement in a fixed order: node, docker, docker compose. Never throws: a tool that cannot be queried fails its check. */
export async function checkRequirements({ nodeVersion, ...docker }: RequirementOptions = {}): Promise<RequirementCheck[]> {
  return [checkNodeVersion(nodeVersion), await checkDockerVersion(docker), await checkComposeVersion(docker)]
}
