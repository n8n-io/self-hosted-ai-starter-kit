import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import { run } from '../src'
import { getLogLevel, setLogLevel } from '../src/utils/logger'

const { verifyMock, configMock, modelsMock, secretsMock, tiltMock } = vi.hoisted(() => ({ verifyMock: vi.fn(), configMock: vi.fn(), modelsMock: vi.fn(), secretsMock: vi.fn(), tiltMock: vi.fn() }))

vi.mock('../src/commands/verify', () => ({ verify: verifyMock }))
vi.mock('../src/commands/config', () => ({ config: configMock }))
vi.mock('../src/commands/models', () => ({ models: modelsMock }))
vi.mock('../src/commands/secrets', () => ({ secrets: secretsMock }))
vi.mock('../src/commands/tilt', () => ({ tilt: tiltMock }))

let logSpy: ReturnType<typeof vi.spyOn>
let errorSpy: ReturnType<typeof vi.spyOn>
let previousExitCode: typeof process.exitCode

beforeEach(() => {
  logSpy = vi.spyOn(console, 'log').mockImplementation(() => {})
  errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
  verifyMock.mockReset()
  configMock.mockReset()
  modelsMock.mockReset()
  secretsMock.mockReset()
  tiltMock.mockReset()
  previousExitCode = process.exitCode
})

afterEach(() => {
  logSpy.mockRestore()
  errorSpy.mockRestore()
  setLogLevel('info')
  process.exitCode = previousExitCode
})

test('prints help with --help', async () => {
  await run(['--help'])
  expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('Usage:'))
})

test('prints help with -h before a command', async () => {
  await run(['-h', 'verify'])
  expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('Usage:'))
  expect(verifyMock).not.toHaveBeenCalled()
})

test('prints help when no command is given', async () => {
  await run([])
  expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('Usage:'))
})

test('prints the version with --version', async () => {
  await run(['--version'])
  expect(logSpy).toHaveBeenCalledWith(expect.stringMatching(/^\d+\.\d+\.\d+/))
})

test('runs a command at the info log level by default', async () => {
  await run(['verify'])

  expect(verifyMock).toHaveBeenCalledOnce()
  expect(getLogLevel()).toBe('info')
})

test.each([
  [['verify'], false],
  [['verify', '--json'], true],
  [['--json', 'verify', '-q'], true],
])('%j passes --json to verify', async (argv, json) => {
  await run(argv)

  expect(verifyMock).toHaveBeenCalledWith(process.cwd(), {}, { json })
})

test.each([
  ['-q', 'verify'],
  ['verify', '-q'],
  ['--quiet', 'verify'],
  ['verify', '--quiet'],
])('%s %s runs the command at the error log level', async (...argv) => {
  await run(argv)

  expect(verifyMock).toHaveBeenCalledOnce()
  expect(getLogLevel()).toBe('error')
})

test.each([
  [['verify', '--log-level', 'debug'], 'debug'],
  [['verify', '--log-level=silent'], 'silent'],
  [['--log-level', 'warn', 'verify'], 'warn'],
])('%j sets the log level to %s', async (argv, level) => {
  await run(argv)

  expect(verifyMock).toHaveBeenCalledOnce()
  expect(getLogLevel()).toBe(level)
})

test('an explicit --log-level wins over --quiet', async () => {
  await run(['verify', '--log-level', 'warn', '--quiet'])

  expect(verifyMock).toHaveBeenCalledOnce()
  expect(getLogLevel()).toBe('warn')
})

test.each([
  ['verify', '--log-level', 'nope'],
  ['verify', '--log-level', 'INFO'],
  ['verify', '--log-level'],
  ['verify', '--no-log-level'],
])('%s %s %s rejects the log level without running the command', async (...argv) => {
  await run(argv)

  expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining('Invalid --log-level'))
  expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining('silent, error, warn, info, debug'))
  expect(process.exitCode).toBe(1)
  expect(verifyMock).not.toHaveBeenCalled()
})

test.each([
  [['config'], []],
  [['config', 'N8N_VARIANT'], ['N8N_VARIANT']],
  [['config', 'N8N_VARIANT', 'enterprise'], ['N8N_VARIANT', 'enterprise']],
  // positionals stay strings and an empty value survives, whatever the flag position
  [['config', 'DOMAIN', '123'], ['DOMAIN', '123']],
  [['config', 'AI_MODELS', ''], ['AI_MODELS', '']],
  [['--log-level', 'error', 'config', 'AI_MODELS', 'a,b'], ['AI_MODELS', 'a,b']],
  [['config', '--log-level=error', 'AI_ENGINE', '-q', 'vllm'], ['AI_ENGINE', 'vllm']],
])('%j passes the sub-command and value %j to config', async (argv, rest) => {
  await run(argv)

  expect(configMock).toHaveBeenCalledWith(process.cwd(), rest)
})

test('passes the sub-command and value to tilt', async () => {
  await run(['tilt', 'resources', '--log-level', 'error'])

  expect(tiltMock).toHaveBeenCalledWith(process.cwd(), ['resources'])
})

test.each([
  [['models', 'read'], modelsMock, ['read'], false],
  [['models', 'read', 'vllm', '--json'], modelsMock, ['read', 'vllm'], true],
  [['models', 'select', 'a,b', '-q'], modelsMock, ['select', 'a,b'], false],
  [['models', 'select', ''], modelsMock, ['select', ''], false],
  [['secrets', 'read', 'vllm'], secretsMock, ['read', 'vllm'], false],
  [['secrets', 'read', 'vllm', '--json'], secretsMock, ['read', 'vllm'], true],
  [['--json', 'secrets', 'read', '-q'], secretsMock, ['read'], true],
  [['secrets', 'set', 'VLLM_API_KEY', 'sk-1', '-q'], secretsMock, ['set', 'VLLM_API_KEY', 'sk-1'], false],
])('%j passes the sub-command, value and --json to the command', async (argv, mock, rest, json) => {
  await run(argv)

  expect(mock).toHaveBeenCalledWith(process.cwd(), rest, { json })
})

test.each([
  ['setup', '--json'],
  ['models', 'select', 'a', '--json'],
  ['secrets', 'set', 'VLLM_API_KEY', 'sk-1', '--json'],
])('%s %s rejects --json without running', async (...argv) => {
  await run(argv)

  expect(errorSpy).toHaveBeenCalledWith('--json is only accepted by verify, models read and secrets read')
  expect(process.exitCode).toBe(1)
  expect(verifyMock).not.toHaveBeenCalled()
  expect(modelsMock).not.toHaveBeenCalled()
  expect(secretsMock).not.toHaveBeenCalled()
})

test('a command without sub-commands rejects extra arguments with its help', async () => {
  await run(['verify', 'extra'])

  expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining('Unknown sub-command "extra" for verify'))
  expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('Usage:\n  n8n-starter verify [--json] [options]'))
  expect(process.exitCode).toBe(1)
  expect(verifyMock).not.toHaveBeenCalled()
})

test.each([
  ['models', 'read, select', modelsMock],
  ['secrets', 'read, set', secretsMock],
  ['tilt', 'resources', tiltMock],
])('%s without a sub-command prints its help with exit code 1', async (command, expected, mock) => {
  await run([command])

  expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining(`Missing sub-command for ${command}. Expected one of: ${expected}`))
  expect(logSpy).toHaveBeenCalledWith(expect.stringContaining(`Usage:\n  n8n-starter ${command} <`))
  expect(process.exitCode).toBe(1)
  expect(mock).not.toHaveBeenCalled()
})

test('an unknown sub-command prints the help of the command with exit code 1', async () => {
  await run(['secrets', 'nope', 'x'])

  expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining('Unknown sub-command "nope" for secrets. Expected one of: read, set'))
  expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('n8n-starter secrets <read|set> [options]'))
  expect(process.exitCode).toBe(1)
  expect(secretsMock).not.toHaveBeenCalled()
})

test.each([
  ['secrets', '-h'],
  ['secrets', 'read', '--help'],
  ['-h', 'secrets'],
  ['help', 'secrets'],
])('%s %s prints the help of secrets with exit code 0 without running', async (...argv) => {
  await run(argv)

  expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('Usage:\n  n8n-starter secrets <read|set> [options]'))
  expect(logSpy).not.toHaveBeenCalledWith(expect.stringContaining('models select'))
  expect(errorSpy).not.toHaveBeenCalled()
  expect(process.exitCode).toBe(previousExitCode)
  expect(secretsMock).not.toHaveBeenCalled()
})

test('help alone prints the global help', async () => {
  await run(['help'])

  expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('n8n-starter <command> [sub-command] [value] [options]'))
  expect(process.exitCode).toBe(previousExitCode)
})

test.each([
  ['help', 'nope'],
  ['hello'],
])('%s %s is an unknown command', async (...argv) => {
  await run(argv)

  expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining(`Unknown command: ${argv.at(-1)}`))
  expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('n8n-starter <command> [sub-command] [value] [options]'))
  expect(process.exitCode).toBe(1)
})
