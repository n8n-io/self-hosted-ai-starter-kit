import { styleText } from 'node:util'

/** The n8n brand accent, the pink of the logo mark and the highlight colour of the CLI */
export const ACCENT = '#FF91AC'

/**
 * Text in the accent colour. styleText decides whether colours are on (plain without a tty or with NO_COLOR,
 * coloured with FORCE_COLOR) but knows named colours only, so the escape code is written here by colour depth:
 * the exact pink at 24 bit, its nearest entry of the 256 colour table (211, #ff87af) at 8 bit and bright
 * magenta below that. Without a tty the depth is 4, which is what a forced colour run gets.
 */
export function accent(text: string, depth = process.stdout.isTTY ? process.stdout.getColorDepth() : 4): string {
  const fallback = styleText('magentaBright', text)
  if (fallback === text)
    return text
  if (depth >= 24) {
    const [red, green, blue] = [1, 3, 5].map(index => Number.parseInt(ACCENT.slice(index, index + 2), 16))
    return `\u001B[38;2;${red};${green};${blue}m${text}\u001B[39m`
  }
  if (depth >= 8)
    return `\u001B[38;5;211m${text}\u001B[39m`
  return fallback
}

/**
 * A `KEY=value` line for stdout with the key in the accent colour of the help table; it stays plain without a tty
 * or with NO_COLOR, so a piped `secrets read` or `models read` carries no escape codes
 */
export function keyValue(key: string, value: string): string {
  return `${accent(key)}=${value}`
}

/**
 * A command hint as the user runs it: the root scripts (`pnpm run <command>`) are the only documented way to run
 * the CLI, there is no global install (see ../../../../SPEC.md), so every "run …" hint names them
 */
export function runCommand(command: string): string {
  return `\`pnpm run ${command}\``
}
