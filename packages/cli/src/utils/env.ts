import { parseEnv } from 'node:util'

export function parseEnvContent(content: string): Record<string, string> {
  return parseEnv(content) as Record<string, string>
}

/** A knob a template shows commented out with its default, `# N8N_PROTOCOL=http` */
const ENV_DEFAULT_LINE = /^# (?=[A-Z][A-Z0-9_]*=)/

/** The commented defaults of a template: what the compose file applies while the .env leaves the key out */
export function parseEnvDefaults(content: string): Record<string, string> {
  const lines = content.split('\n').filter(line => ENV_DEFAULT_LINE.test(line)).map(line => line.replace(ENV_DEFAULT_LINE, ''))
  return parseEnvContent(lines.join('\n'))
}

/** What docker compose or node read as syntax in an unquoted value: `$` is interpolated, `#` starts a comment */
const ENV_UNQUOTED_UNSAFE = /[\s#$"'`\\]/
/** What no quoting stores the same way for docker compose and for node */
const ENV_UNSTORABLE = /['\\\n\r]/

/**
 * A value as it is written after `KEY=`: as it is when every reader takes it literally, in single quotes otherwise
 * (docker compose reads those without interpolation, so the `$` of a bcrypt hash survive). Throws on a value that
 * cannot be stored unambiguously; the message never holds the value.
 */
export function formatEnvValue(value: string): string {
  if (!ENV_UNQUOTED_UNSAFE.test(value))
    return value
  if (ENV_UNSTORABLE.test(value))
    throw new Error('the value must not hold a single quote, a backslash or a line break')
  return `'${value}'`
}

const ENV_LINE = /^([A-Z_][A-Z0-9_]*)=/i

/**
 * Replaces the values of the given keys in a .env file's content while
 * preserving comments, blank lines and unrelated keys. Keys that are not
 * present yet are appended at the end.
 */
export function updateEnvContent(content: string, updates: Record<string, string>): string {
  const remaining = new Map(Object.entries(updates).map(([key, value]) => [key, formatEnvValue(value)]))

  const lines = content.split('\n').map((line) => {
    const key = line.match(ENV_LINE)?.[1]
    if (key === undefined || !remaining.has(key))
      return line
    const value = remaining.get(key)!
    remaining.delete(key)
    return `${key}=${value}`
  })

  let updated = lines.join('\n')
  if (remaining.size > 0) {
    if (updated.length > 0 && !updated.endsWith('\n'))
      updated += '\n'
    for (const [key, value] of remaining)
      updated += `${key}=${value}\n`
  }

  return updated
}
