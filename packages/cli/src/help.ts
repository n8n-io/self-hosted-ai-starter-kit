import { styleText } from 'node:util'

/**
 * The command table of the CLI: one entry per command, rendered as the global help (`--help`, `help`)
 * and as the help of one command (`<command> --help`, `help <command>`, or a command called without the
 * sub-command it needs). Mirrored by the tables of ../README.md and ../../../SPEC.md.
 */
export interface SubcommandHelp {
  name: string
  usage: string
  description: string
}

export interface CommandHelp {
  usage: string
  description: string
  /** Extra lines under the command in the global help, such as the keys config accepts */
  notes?: readonly string[]
  /** The sub-commands a command requires; a command without them runs on its own */
  subcommands?: readonly SubcommandHelp[]
}

export const COMMAND_HELP = {
  setup: { usage: 'setup', description: 'Generate .env files from .env.template files (AI_RUNTIME of a new root .env from the detected platform), fill their secrets and create the docker networks' },
  verify: { usage: 'verify [--json]', description: 'Check the node, docker and docker compose versions and that every .env file, every secret and the docker networks exist (exit code 1 if not), warn when AI_RUNTIME does not match the detected platform; --json one report { ok, success, info, warnings, errors, hints }' },
  reset: { usage: 'reset', description: 'Delete all generated .env files' },
  config: {
    usage: 'config [KEY] [value]',
    description: 'Edit the root .env: no KEY asks which key, KEY prompts that key only, KEY value writes it without a prompt; AI_RUNTIME marks the detected runtime and warns about a mismatch, AI_MODELS runs models select',
    notes: ['KEY: N8N_VARIANT, AI_RUNTIME, AI_ENGINE, AI_GATEWAY, AI_MODELS or DOMAIN'],
  },
  models: {
    usage: 'models <read|select>',
    description: 'Read the model catalogue and pick AI_MODELS of the root .env',
    subcommands: [
      { name: 'read', usage: 'models read [filter] [--json]', description: 'Print the models of compose/models/models.json as key=value lines under an engine/id header, filtered by a part of an engine or id; --json an array of { engine, id, model, label, ... }' },
      { name: 'select', usage: 'models select [ids]', description: 'Pick AI_MODELS of the root .env: a multi-select over the catalogue against the detected docker memory, or comma separated ids written without a prompt ("" clears)' },
    ],
  },
  secrets: {
    usage: 'secrets <read|set>',
    description: 'Read and set the secrets of the .env files declared in the .env.secrets.json manifests',
    subcommands: [
      { name: 'read', usage: 'secrets read [filter] [--json]', description: 'Print the secrets of the .env files as KEY=value, filtered by a part of a directory or key; an exact key prints only its value, --json an array of { file, key, value, source }' },
      { name: 'set', usage: 'secrets set KEY [value]', description: 'Set one secret of the .env.secrets.json manifests: KEY alone asks for it with a masked prompt, KEY value writes without a prompt' },
    ],
  },
  tilt: {
    usage: 'tilt <resources>',
    description: 'The plan the Tiltfile consumes',
    subcommands: [
      { name: 'resources', usage: 'tilt resources', description: 'Print the Tilt resource plan of the root .env as JSON for the Tiltfile (exit code 1 when the .env or AI_MODELS is invalid)' },
    ],
  },
} as const satisfies Record<string, CommandHelp>

export type Command = keyof typeof COMMAND_HELP

/** Every command, in help order */
export const COMMANDS = Object.keys(COMMAND_HELP) as Command[]

export const OPTIONS = [
  { usage: '-h, --help', description: 'Show this help message, or the help of the command named with it' },
  { usage: '-v, --version', description: 'Show the version number' },
  { usage: '-q, --quiet', description: 'Only log errors (same as --log-level error)' },
  { usage: '    --log-level <lvl>', description: 'One of silent, error, warn, info or debug (default: info)' },
  { usage: '    --json', description: 'Print JSON instead of text (verify, models read and secrets read)' },
] as const

export function isCommand(value: string | undefined): value is Command {
  return value !== undefined && (COMMANDS as string[]).includes(value)
}

export function commandHelp(command: Command): CommandHelp {
  return COMMAND_HELP[command]
}

/** The sub-command names a command requires, empty for a command that runs on its own */
export function subcommandNames(command: Command): string[] {
  return commandHelp(command).subcommands?.map(subcommand => subcommand.name) ?? []
}

interface Row {
  usage: string
  description: string
  notes?: readonly string[]
}

/**
 * Two-column rows, the descriptions aligned two spaces after the longest usage and notes under the
 * description. The usage column is highlighted so a wrapped description does not blur the list;
 * styleText stays plain without a tty or with NO_COLOR, and the padding counts the plain length.
 */
function table(rows: readonly Row[]): string[] {
  const width = Math.max(...rows.map(row => row.usage.length)) + 2
  return rows.flatMap(row => [
    `  ${styleText('cyan', row.usage)}${''.padEnd(width - row.usage.length)}${row.description}`,
    ...(row.notes ?? []).map(note => `  ${''.padEnd(width)}${note}`),
  ])
}

/** The global help, or the help of one command; both end with the options and a trailing newline */
export function renderHelp(command?: Command): string {
  const options = ['Options:', ...table(OPTIONS), '']
  if (command === undefined) {
    const rows = COMMANDS.flatMap((name): Row[] => {
      const help = commandHelp(name)
      return help.subcommands?.map(({ usage, description }) => ({ usage, description })) ?? [help]
    })
    return ['n8n-starter', '', 'Usage:', '  n8n-starter <command> [sub-command] [value] [options]', '', 'Commands:', ...table(rows), '', ...options].join('\n')
  }
  const help = commandHelp(command)
  const body = help.subcommands
    ? [help.description, '', 'Sub-commands:', ...table(help.subcommands.map(({ usage, description }) => ({ usage, description }))), '']
    : [help.description, ...(help.notes ?? []).map(note => `  ${note}`), '']
  return [`n8n-starter ${command}`, '', 'Usage:', `  n8n-starter ${help.usage} [options]`, '', ...body, ...options].join('\n')
}
