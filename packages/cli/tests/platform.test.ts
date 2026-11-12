import type { DockerRunner } from '../src/utils/docker'
import { expect, test } from 'vitest'
import { AMD_GPU_DEVICE, bytesToGb, detectGpu, detectPlatform, DOCKER_INFO_FORMAT, formatPlatform, normaliseArch, parseDockerInfo, runtimeMismatch, suggestRuntime } from '../src/utils/platform'

const GB = 1024 ** 3

/** The line of this repository's development machine (OrbStack on Apple silicon) */
const ORBSTACK = 'aarch64|14709911552|6|OrbStack|io.containerd.runc.v2,runc,\n'
/** A Linux workstation with the NVIDIA Container Toolkit */
const NVIDIA = 'x86_64|67353571328|16|Ubuntu 24.04.1 LTS|io.containerd.runc.v2,nvidia,runc,'

const HOST = { arch: 'arm64', os: 'darwin' as const, totalmem: 24 * GB, exists: async () => false }

function fakeInfo(line: string): DockerRunner {
  return async (args) => {
    expect(args).toEqual(['info', '--format', DOCKER_INFO_FORMAT])
    return line
  }
}

test('parses the fields of the docker info line', () => {
  expect(parseDockerInfo(ORBSTACK)).toEqual({ arch: 'aarch64', memory: 14709911552, cpus: 6, os: 'OrbStack', runtimes: ['io.containerd.runc.v2', 'runc'] })
  expect(parseDockerInfo(NVIDIA)).toMatchObject({ arch: 'x86_64', cpus: 16, runtimes: ['io.containerd.runc.v2', 'nvidia', 'runc'] })
  expect(parseDockerInfo('')).toBeUndefined()
  expect(parseDockerInfo('garbage')).toBeUndefined()
  expect(parseDockerInfo('aarch64|lots|6|OrbStack|runc,')).toBeUndefined()
})

test('normalises the docker and node architecture names', () => {
  expect(normaliseArch('aarch64')).toBe('arm64')
  expect(normaliseArch('arm64')).toBe('arm64')
  expect(normaliseArch('x86_64')).toBe('x86-64')
  expect(normaliseArch('amd64')).toBe('x86-64')
  expect(normaliseArch('x64')).toBe('x86-64')
  expect(normaliseArch('riscv64')).toBeUndefined()
  expect(bytesToGb(14709911552)).toBe(14)
  expect(bytesToGb(16 * GB)).toBe(16)
})

test('detects a gpu from the nvidia docker runtime or the ROCm device of a Linux host', async () => {
  const nvidia = parseDockerInfo(NVIDIA)
  const plain = parseDockerInfo(ORBSTACK)
  const paths: string[] = []
  const kfd = async (path: string) => {
    paths.push(path)
    return true
  }

  expect(await detectGpu(nvidia, 'linux', async () => false)).toBe('nvidia')
  expect(await detectGpu(plain, 'linux', kfd)).toBe('amd')
  expect(paths).toEqual([AMD_GPU_DEVICE])
  // macOS never passes a gpu to docker, whatever the device list says
  expect(await detectGpu(plain, 'darwin', kfd)).toBeUndefined()
  expect(await detectGpu(undefined, 'linux', async () => false)).toBeUndefined()
})

test('suggests the runtime of the platform, a gpu before the cpu architecture', () => {
  expect(suggestRuntime({ arch: 'x86-64', gpu: 'nvidia' })).toBe('gpu-nvidia')
  expect(suggestRuntime({ arch: 'x86-64', gpu: 'amd' })).toBe('gpu-amd')
  expect(suggestRuntime({ arch: 'arm64' })).toBe('cpu-arm64')
  expect(suggestRuntime({ arch: 'x86-64' })).toBe('cpu-x86-64')
  expect(suggestRuntime({})).toBeUndefined()
})

test('detectPlatform reads the daemon and falls back to the host when it cannot', async () => {
  const orbstack = await detectPlatform({ run: fakeInfo(ORBSTACK), ...HOST })
  const nvidia = await detectPlatform({ run: fakeInfo(NVIDIA), arch: 'x64', os: 'linux', totalmem: 64 * GB, exists: async () => false })
  const down = await detectPlatform({ run: async () => {
    throw new Error('Cannot connect to the Docker daemon')
  }, ...HOST })
  const garbage = await detectPlatform({ run: async () => 'nope', arch: 'x64', os: 'linux', totalmem: 8 * GB, exists: async path => path === AMD_GPU_DEVICE })

  expect(orbstack).toEqual({
    host: { os: 'darwin', arch: 'arm64', memory: 24 * GB },
    docker: parseDockerInfo(ORBSTACK),
    gpu: undefined,
    arch: 'arm64',
    runtime: 'cpu-arm64',
    memory: 14,
  })
  expect(nvidia).toMatchObject({ gpu: 'nvidia', arch: 'x86-64', runtime: 'gpu-nvidia', memory: 63 })
  expect(down).toEqual({ host: { os: 'darwin', arch: 'arm64', memory: 24 * GB }, docker: undefined, gpu: undefined, arch: 'arm64', runtime: 'cpu-arm64', memory: undefined })
  // the host still tells the architecture and the gpu device
  expect(garbage).toMatchObject({ docker: undefined, gpu: 'amd', arch: 'x86-64', runtime: 'gpu-amd', memory: undefined })
})

test('formats the platform in one line and names the mismatch with its fix', async () => {
  const orbstack = await detectPlatform({ run: fakeInfo(ORBSTACK), ...HOST })
  const nvidia = await detectPlatform({ run: fakeInfo(NVIDIA), arch: 'x64', os: 'linux', totalmem: 64 * GB, exists: async () => false })
  const down = await detectPlatform({ run: async () => {
    throw new Error('down')
  }, ...HOST })

  expect(formatPlatform(orbstack)).toBe('docker aarch64, 6 cpus, 14 GB memory (OrbStack), host darwin/arm64 24 GB, no gpu')
  expect(formatPlatform(nvidia)).toBe('docker x86_64, 16 cpus, 63 GB memory (Ubuntu 24.04.1 LTS), host linux/x64 64 GB, nvidia gpu')
  expect(formatPlatform(down)).toBe('no docker info, host darwin/arm64 24 GB, no gpu')

  expect(runtimeMismatch(orbstack, 'cpu-arm64')).toBeUndefined()
  expect(runtimeMismatch(orbstack, 'cpu-x86-64')).toBe('AI_RUNTIME=cpu-x86-64 does not match the detected platform (docker aarch64, 6 cpus, 14 GB memory (OrbStack), host darwin/arm64 24 GB, no gpu), run `pnpm run config AI_RUNTIME cpu-arm64`')
  expect(runtimeMismatch(nvidia, 'cpu-x86-64')).toContain('run `pnpm run config AI_RUNTIME gpu-nvidia`')
  // nothing suggested, nothing to warn about
  expect(runtimeMismatch({ ...orbstack, runtime: undefined }, 'gpu-amd')).toBeUndefined()
})
