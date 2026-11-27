import type { AiRuntime } from '../schemas/config'
import type { DockerOptions } from './docker'
import { access } from 'node:fs/promises'
import { arch as hostArch, platform as hostOs, totalmem } from 'node:os'
import { runDocker } from './docker'
import { runCommand } from './format'
import { logger } from './logger'

/**
 * One line of `docker info`: the daemon's architecture (`aarch64`, `x86_64`), the memory of the Docker VM (the
 * host memory on native Linux), its cpus, the operating system and the registered runtimes, where the NVIDIA
 * Container Toolkit registers `nvidia` (see ../../../../SPEC.md)
 */
export const DOCKER_INFO_FORMAT = '{{.Architecture}}|{{.MemTotal}}|{{.NCPU}}|{{.OperatingSystem}}|{{range $k, $v := .Runtimes}}{{$k}},{{end}}'

/** The ROCm device the gpu-amd compose services mount; present on a Linux host with an AMD GPU */
export const AMD_GPU_DEVICE = '/dev/kfd'

export interface DockerInfo {
  arch: string
  /** Bytes */
  memory: number
  cpus: number
  os: string
  runtimes: string[]
}

export type Arch = 'arm64' | 'x86-64'
export type Gpu = 'nvidia' | 'amd'

export interface Platform {
  host: { os: NodeJS.Platform, arch: string, memory: number }
  /** Absent when the daemon could not be queried */
  docker?: DockerInfo
  gpu?: Gpu
  /** The normalised architecture of the daemon, or of the host without one */
  arch?: Arch
  /** The AI_RUNTIME that fits the platform; absent when the architecture is unknown */
  runtime?: AiRuntime
  /** The memory of the Docker VM in GB, the figure the catalogue estimates compare with */
  memory?: number
}

export interface PlatformOptions extends DockerOptions {
  /** The host values to use instead of the running machine's (tests) */
  arch?: string
  os?: NodeJS.Platform
  totalmem?: number
  exists?: (path: string) => Promise<boolean>
}

async function fileExists(path: string): Promise<boolean> {
  try {
    await access(path)
    return true
  } catch {
    return false
  }
}

export function bytesToGb(bytes: number): number {
  return Math.round(bytes / 1024 ** 3)
}

/** The fields of DOCKER_INFO_FORMAT; undefined when the line does not have them */
export function parseDockerInfo(stdout: string): DockerInfo | undefined {
  const parts = stdout.trim().split('|')
  if (parts.length !== 5)
    return undefined
  const [arch, memory, cpus, os, runtimes] = parts as [string, string, string, string, string]
  if (arch === '' || !/^\d+$/.test(memory) || !/^\d+$/.test(cpus))
    return undefined
  return { arch, memory: Number(memory), cpus: Number(cpus), os, runtimes: runtimes.split(',').filter(name => name !== '') }
}

/** `aarch64` and `arm64` (docker, node) are arm64; `x86_64`, `amd64` and `x64` are x86-64 */
export function normaliseArch(value: string): Arch | undefined {
  switch (value.toLowerCase()) {
    case 'aarch64':
    case 'arm64':
      return 'arm64'
    case 'x86_64':
    case 'amd64':
    case 'x64':
      return 'x86-64'
    default:
      return undefined
  }
}

/** nvidia when the daemon registered the `nvidia` runtime, amd when a Linux host has the ROCm device */
export async function detectGpu(docker: DockerInfo | undefined, os: NodeJS.Platform, exists: (path: string) => Promise<boolean> = fileExists): Promise<Gpu | undefined> {
  if (docker?.runtimes.includes('nvidia'))
    return 'nvidia'
  if (os === 'linux' && await exists(AMD_GPU_DEVICE))
    return 'amd'
  return undefined
}

/** The runtime of the platform: a gpu wins over the cpu architecture; nothing for an unknown architecture */
export function suggestRuntime({ arch, gpu }: { arch?: Arch, gpu?: Gpu }): AiRuntime | undefined {
  if (gpu === 'nvidia')
    return 'gpu-nvidia'
  if (gpu === 'amd')
    return 'gpu-amd'
  if (arch === 'arm64')
    return 'cpu-arm64'
  if (arch === 'x86-64')
    return 'cpu-x86-64'
  return undefined
}

/**
 * The platform the stack would run on. Never throws: without a reachable daemon the host architecture
 * stands in for the suggestion and the docker figures are absent.
 */
export async function detectPlatform({ run = runDocker, arch = hostArch(), os = hostOs(), totalmem: hostMemory = totalmem(), exists = fileExists }: PlatformOptions = {}): Promise<Platform> {
  let docker: DockerInfo | undefined
  try {
    docker = parseDockerInfo(await run(['info', '--format', DOCKER_INFO_FORMAT]))
  } catch (error) {
    logger.debug(`docker info failed: ${((error as Error).message ?? String(error)).split('\n')[0]}`)
  }
  const gpu = await detectGpu(docker, os, exists)
  const normalised = normaliseArch(docker?.arch ?? arch)
  return {
    host: { os, arch, memory: hostMemory },
    docker,
    gpu,
    arch: normalised,
    runtime: suggestRuntime({ arch: normalised, gpu }),
    memory: docker === undefined ? undefined : bytesToGb(docker.memory),
  }
}

/** One line: `docker aarch64, 6 cpus, 14 GB memory (OrbStack), host darwin/arm64 24 GB, no gpu` */
export function formatPlatform({ host, docker, gpu, memory }: Platform): string {
  return [
    docker === undefined ? 'no docker info' : `docker ${docker.arch}, ${docker.cpus} cpus, ${memory} GB memory (${docker.os})`,
    `host ${host.os}/${host.arch} ${bytesToGb(host.memory)} GB`,
    gpu === undefined ? 'no gpu' : `${gpu} gpu`,
  ].join(', ')
}

/**
 * The warning for an AI_RUNTIME that is not the one the platform suggests, naming the config command that
 * sets it; nothing when they agree or nothing was suggested. A warning only: cpu-x86-64 on Apple silicon
 * (emulation) and a cpu runtime on a gpu machine are legitimate choices (see ../../../../SPEC.md).
 */
export function runtimeMismatch(platform: Platform, current: AiRuntime): string | undefined {
  if (platform.runtime === undefined || platform.runtime === current)
    return undefined
  return `AI_RUNTIME=${current} does not match the detected platform (${formatPlatform(platform)}), run ${runCommand(`config AI_RUNTIME ${platform.runtime}`)}`
}
