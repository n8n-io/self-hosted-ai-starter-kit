import * as clack from '@clack/prompts'
import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import { DEFAULT_LOG_LEVEL, getLogLevel, HINT_SYMBOL, LOG_LEVELS, logger, parseLogLevel, setLogLevel } from '../src/utils/logger'

vi.mock('@clack/prompts', () => ({
  intro: vi.fn(),
  outro: vi.fn(),
  cancel: vi.fn(),
  log: { success: vi.fn(), info: vi.fn(), step: vi.fn(), warn: vi.fn(), error: vi.fn(), message: vi.fn() },
}))

beforeEach(() => {
  vi.clearAllMocks()
})

afterEach(() => {
  setLogLevel(DEFAULT_LOG_LEVEL)
})

const sinks = {
  intro: clack.intro,
  outro: clack.outro,
  cancel: clack.cancel,
  success: clack.log.success,
  info: clack.log.info,
  step: clack.log.step,
  warn: clack.log.warn,
  error: clack.log.error,
  message: clack.log.message,
}

function logEverything() {
  logger.intro('intro')
  logger.outro('outro')
  logger.success('success')
  logger.info('info')
  logger.step('step')
  logger.warn('warn')
  logger.cancel('cancel')
  logger.error('error')
  logger.hint('hint')
  logger.debug('debug')
}

function calledSinks(): string[] {
  return Object.entries(sinks)
    .filter(([, fn]) => vi.mocked(fn).mock.calls.length > 0)
    .map(([name]) => name)
    .sort()
}

test('defaults to the info level', () => {
  expect(DEFAULT_LOG_LEVEL).toBe('info')
  expect(getLogLevel()).toBe('info')
})

test('levels are ordered from least to most verbose', () => {
  expect(LOG_LEVELS).toEqual(['silent', 'error', 'warn', 'info', 'debug'])
})

test.each([
  ['silent', []],
  ['error', ['error', 'message']],
  ['warn', ['cancel', 'error', 'message', 'warn']],
  ['info', ['cancel', 'error', 'info', 'intro', 'message', 'outro', 'step', 'success', 'warn']],
  ['debug', ['cancel', 'error', 'info', 'intro', 'message', 'outro', 'step', 'success', 'warn']],
] as const)('at level %s only the expected clack calls go through', (level, expected) => {
  setLogLevel(level)

  logEverything()

  expect(getLogLevel()).toBe(level)
  expect(calledSinks()).toEqual([...expected])
})

test('passes messages through unchanged', () => {
  setLogLevel('debug')

  logEverything()

  expect(clack.intro).toHaveBeenCalledWith('intro')
  expect(clack.log.error).toHaveBeenCalledWith('error')
  expect(clack.cancel).toHaveBeenCalledWith('cancel')
  expect(clack.log.message).toHaveBeenCalledWith('hint', { symbol: HINT_SYMBOL })
  expect(clack.log.message).toHaveBeenCalledWith('debug', { symbol: '○' })
})

test('hint is logged from the error level on and debug only at debug', () => {
  setLogLevel('error')
  logger.hint('hint')
  logger.debug('debug')

  expect(vi.mocked(clack.log.message).mock.calls).toEqual([['hint', { symbol: HINT_SYMBOL }]])
})

test('parseLogLevel accepts exactly the known level names', () => {
  for (const level of LOG_LEVELS)
    expect(parseLogLevel(level)).toBe(level)

  expect(parseLogLevel('')).toBeUndefined()
  expect(parseLogLevel('INFO')).toBeUndefined()
  expect(parseLogLevel('verbose')).toBeUndefined()
  expect(parseLogLevel(undefined)).toBeUndefined()
  expect(parseLogLevel(false)).toBeUndefined()
  expect(parseLogLevel(true)).toBeUndefined()
})
