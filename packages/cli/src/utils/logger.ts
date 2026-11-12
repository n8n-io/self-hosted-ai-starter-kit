import { cancel, intro, log, outro } from '@clack/prompts'

export const LOG_LEVELS = ['silent', 'error', 'warn', 'info', 'debug'] as const

export type LogLevel = typeof LOG_LEVELS[number]

export const DEFAULT_LOG_LEVEL: LogLevel = 'info'

let currentLevel: LogLevel = DEFAULT_LOG_LEVEL

/** The symbol of a hint line; the Tiltfile marks the hints of the verify report the same way (see ../../../../SPEC.md) */
export const HINT_SYMBOL = '💡'

export function parseLogLevel(value: unknown): LogLevel | undefined {
  return LOG_LEVELS.find(level => level === value)
}

export function setLogLevel(level: LogLevel): void {
  currentLevel = level
}

export function getLogLevel(): LogLevel {
  return currentLevel
}

function enabled(level: Exclude<LogLevel, 'silent'>): boolean {
  return LOG_LEVELS.indexOf(level) <= LOG_LEVELS.indexOf(currentLevel)
}

/**
 * Process-wide, level-gated wrapper around the clack log output. Interactive
 * prompts are not part of it: they are input, not output, and are never
 * silenced.
 */
export const logger = {
  intro(title: string): void {
    if (enabled('info'))
      intro(title)
  },
  outro(message: string): void {
    if (enabled('info'))
      outro(message)
  },
  success(message: string): void {
    if (enabled('info'))
      log.success(message)
  },
  info(message: string): void {
    if (enabled('info'))
      log.info(message)
  },
  step(message: string): void {
    if (enabled('info'))
      log.step(message)
  },
  warn(message: string): void {
    if (enabled('warn'))
      log.warn(message)
  },
  cancel(message: string): void {
    if (enabled('warn'))
      cancel(message)
  },
  error(message: string): void {
    if (enabled('error'))
      log.error(message)
  },
  /** A fix for a reported error: logged at the error level so a `--log-level error` run still names it, marked 💡 instead of the red error square */
  hint(message: string): void {
    if (enabled('error'))
      log.message(message, { symbol: HINT_SYMBOL })
  },
  debug(message: string): void {
    if (enabled('debug'))
      log.message(message, { symbol: '○' })
  },
}
