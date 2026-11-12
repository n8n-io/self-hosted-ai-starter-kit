import { styleText } from 'node:util'

/**
 * A `KEY=value` line for stdout with the key in the cyan of the help table; styleText stays plain without a tty
 * or with NO_COLOR, so a piped `secrets read` or `models read` carries no escape codes
 */
export function keyValue(key: string, value: string): string {
  return `${styleText('cyan', key)}=${value}`
}

/**
 * A command hint as the user runs it: the root scripts (`pnpm run <command>`) are the only documented way to run
 * the CLI, there is no global install (see ../../../../SPEC.md), so every "run …" hint names them
 */
export function runCommand(command: string): string {
  return `\`pnpm run ${command}\``
}
