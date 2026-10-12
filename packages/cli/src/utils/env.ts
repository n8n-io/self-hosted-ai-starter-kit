import { parseEnv } from 'node:util'

export function parseEnvContent(content: string): Record<string, string> {
  return parseEnv(content) as Record<string, string>
}

const ENV_LINE = /^([A-Z_][A-Z0-9_]*)=/i

/**
 * Replaces the values of the given keys in a .env file's content while
 * preserving comments, blank lines and unrelated keys. Keys that are not
 * present yet are appended at the end.
 */
export function updateEnvContent(content: string, updates: Record<string, string>): string {
  const remaining = new Map(Object.entries(updates))

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
