import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import { run } from '../src'

let logSpy: ReturnType<typeof vi.spyOn>

beforeEach(() => {
  logSpy = vi.spyOn(console, 'log').mockImplementation(() => {})
})

afterEach(() => {
  logSpy.mockRestore()
})

test('prints help with --help', async () => {
  await run(['--help'])
  expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('Usage:'))
})

test('prints help when no command is given', async () => {
  await run([])
  expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('Usage:'))
})

test('prints the version with --version', async () => {
  await run(['--version'])
  expect(logSpy).toHaveBeenCalledWith(expect.stringMatching(/^\d+\.\d+\.\d+/))
})
