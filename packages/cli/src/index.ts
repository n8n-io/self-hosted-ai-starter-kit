#!/usr/bin/env node
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { parse } from '@bomb.sh/args'
import { config } from './commands/config'
import { models } from './commands/models'
import { reset } from './commands/reset'
import { secrets } from './commands/secrets'
import { setup } from './commands/setup'
import { tilt } from './commands/tilt'
import { verify } from './commands/verify'
import { isCommand, renderHelp, subcommandNames } from './help'
import { DEFAULT_LOG_LEVEL, LOG_LEVELS, parseLogLevel, setLogLevel } from './utils/logger'

function getVersion(): string {
  const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf-8'))
  return pkg.version
}

/**
 * The command, its sub-command and value as given: the parser coerces positionals (123 to a number,
 * "" dropped, everything after -- dropped), so they are read from argv, skipping the flags and the
 * value of --log-level
 */
export function positionals(argv: string[]): string[] {
  const result: string[] = []
  for (let i = 0; i < argv.length; i++) {
    const token = argv[i]!
    if (token === '--log-level')
      i++
    else if (!token.startsWith('-'))
      result.push(token)
  }
  return result
}

/** The commands that take positional arguments: config its key and value, the others a sub-command and a value */
function takesPositionals(command: string): boolean {
  return command === 'config' || (isCommand(command) && subcommandNames(command).length > 0)
}

/** A usage error: the reason on stderr, the help of the command (or the global one) on stdout, exit code 1 */
function usageError(reason: string, help: string) {
  console.error(`${reason}\n`)
  console.log(help)
  process.exitCode = 1
}

export async function run(argv: string[]) {
  const args = parse(argv, {
    // The parser types a flag by its raw key before resolving aliases, so a
    // short alias that is not listed here would swallow the next token as its value
    boolean: ['help', 'version', 'quiet', 'json', 'h', 'v', 'q'],
    string: ['log-level'],
    alias: { h: 'help', v: 'version', q: 'quiet' },
  })

  const [command, ...rest] = positionals(argv)

  if (args.version) {
    console.log(getVersion())
    return
  }

  // `--help` and `help` show the help of the command they name, the global one otherwise
  if (args.help || command === undefined || command === 'help') {
    const target = command === 'help' ? rest[0] : command
    if (target !== undefined && !isCommand(target)) {
      usageError(`Unknown command: ${target}`, renderHelp())
      return
    }
    console.log(renderHelp(target))
    return
  }

  // A bare `--log-level` parses to "" and `--no-log-level` to false; both are rejected below
  const rawLevel = args['log-level'] as unknown
  const level = rawLevel === undefined
    ? (args.quiet ? 'error' : DEFAULT_LOG_LEVEL)
    : parseLogLevel(rawLevel)

  if (level === undefined) {
    console.error(`Invalid --log-level "${rawLevel}". Expected one of: ${LOG_LEVELS.join(', ')}`)
    process.exitCode = 1
    return
  }

  setLogLevel(level)

  if (!isCommand(command)) {
    usageError(`Unknown command: ${command}`, renderHelp())
    return
  }

  if (!takesPositionals(command) && rest.length > 0) {
    usageError(`Unknown sub-command "${rest[0]}" for ${command}`, renderHelp(command))
    return
  }

  // a command that needs a sub-command shows its own help when called without one or with an unknown one
  const subcommands = subcommandNames(command)
  if (subcommands.length > 0 && rest[0] === undefined) {
    usageError(`Missing sub-command for ${command}. Expected one of: ${subcommands.join(', ')}`, renderHelp(command))
    return
  }
  if (subcommands.length > 0 && !subcommands.includes(rest[0]!)) {
    usageError(`Unknown sub-command "${rest[0]}" for ${command}. Expected one of: ${subcommands.join(', ')}`, renderHelp(command))
    return
  }

  const json = args.json === true
  if (json && !(command === 'verify' || ((command === 'models' || command === 'secrets') && rest[0] === 'read'))) {
    console.error('--json is only accepted by verify, models read and secrets read')
    process.exitCode = 1
    return
  }

  switch (command) {
    case 'setup':
      await setup()
      break
    case 'verify':
      await verify(process.cwd(), {}, { json })
      break
    case 'reset':
      await reset()
      break
    case 'config':
      await config(process.cwd(), rest)
      break
    case 'models':
      await models(process.cwd(), rest, { json })
      break
    case 'secrets':
      await secrets(process.cwd(), rest, { json })
      break
    case 'tilt':
      await tilt(process.cwd(), rest)
      break
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  run(process.argv.slice(2))
}
