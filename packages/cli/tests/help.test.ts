import { expect, test } from 'vitest'
import { CONFIG_KEYS } from '../src/commands/config'
import { MODELS_SUBCOMMANDS } from '../src/commands/models'
import { SECRETS_SUBCOMMANDS } from '../src/commands/secrets'
import { TILT_SUBCOMMANDS } from '../src/commands/tilt'
import { commandHelp, COMMANDS, isCommand, OPTIONS, renderHelp, subcommandNames } from '../src/help'

/** The help without the colour codes of the usage column (present when the test runner forces colours) */
function plain(text: string): string {
  return text.replace(/\u001B\[\d+m/g, '')
}

test('the table lists every command with the sub-commands of its module and the keys of config', () => {
  expect(COMMANDS).toEqual(['setup', 'verify', 'reset', 'config', 'models', 'secrets', 'tilt'])
  expect(subcommandNames('models')).toEqual([...MODELS_SUBCOMMANDS])
  expect(subcommandNames('secrets')).toEqual([...SECRETS_SUBCOMMANDS])
  expect(subcommandNames('tilt')).toEqual([...TILT_SUBCOMMANDS])
  expect(subcommandNames('setup')).toEqual([])
  expect(subcommandNames('config')).toEqual([])
  for (const key of CONFIG_KEYS)
    expect(commandHelp('config').notes?.join(' '), key).toContain(key)
  expect(isCommand('secrets')).toBe(true)
  expect(isCommand('hello')).toBe(false)
  expect(isCommand('toString')).toBe(false)
  expect(isCommand(undefined)).toBe(false)
})

test('the global help lists every command, sub-command and option in one aligned table', () => {
  const help = plain(renderHelp())

  expect(help).toContain('Usage:\n  n8n-starter <command> [sub-command] [value] [options]')
  for (const command of COMMANDS) {
    const entry = commandHelp(command)
    for (const row of entry.subcommands ?? [entry])
      expect(help, row.usage).toContain(`\n  ${row.usage} `)
    for (const note of entry.notes ?? [])
      expect(help, note).toContain(note)
  }
  for (const option of OPTIONS)
    expect(help, option.usage).toContain(`\n  ${option.usage}`)
  expect(help).not.toContain('hello')
  expect(help.endsWith('\n')).toBe(true)
  // within a block every description (and note) starts in the same column
  const lines = help.split('\n')
  for (const heading of ['Commands:', 'Options:']) {
    const start = lines.indexOf(heading) + 1
    const block = lines.slice(start, lines.indexOf('', start))
    expect(block.length, heading).toBeGreaterThan(2)
    // the padding before a description is the last run of two spaces in the line
    expect(new Set(block.map(line => line.lastIndexOf('  ') + 2)).size, heading).toBe(1)
  }
})

test('the help of one command shows its usage, its sub-commands or notes, and the options', () => {
  const secrets = plain(renderHelp('secrets'))
  expect(secrets).toContain('n8n-starter secrets\n\nUsage:\n  n8n-starter secrets <read|set> [options]')
  expect(secrets).toContain('Sub-commands:')
  expect(secrets).toContain('  secrets read [filter] [--json]')
  expect(secrets).toContain('  secrets set KEY [value]')
  expect(secrets).toContain('  --log-level')
  expect(secrets).not.toContain('models select')

  const verify = plain(renderHelp('verify'))
  expect(verify).toContain('Usage:\n  n8n-starter verify [--json] [options]')
  expect(verify).not.toContain('Sub-commands:')
  expect(verify).toContain(commandHelp('verify').description)

  expect(plain(renderHelp('config'))).toContain('  KEY: N8N_VARIANT, AI_RUNTIME, AI_ENGINE, AI_GATEWAY, AI_MODELS or DOMAIN')
})

test('the usage column is highlighted when colours are on and plain when they are off', () => {
  const previous = { FORCE_COLOR: process.env.FORCE_COLOR, NO_COLOR: process.env.NO_COLOR }
  try {
    // FORCE_COLOR wins over NO_COLOR and the missing tty, see util.styleText
    process.env.FORCE_COLOR = '1'
    delete process.env.NO_COLOR
    const coloured = renderHelp('secrets')
    expect(coloured).toContain('  \u001B[36msecrets read [filter] [--json]\u001B[39m  Print')
    expect(coloured).toContain('  \u001B[36m-h, --help\u001B[39m')
    expect(coloured).not.toContain('\u001B[36mUsage:')
    // the padding is computed on the plain usage, so the columns still line up once the codes are gone
    const rows = plain(coloured).split('\n').filter(line => line.startsWith('  secrets '))
    expect(new Set(rows.map(line => line.lastIndexOf('  ') + 2)).size).toBe(1)

    delete process.env.FORCE_COLOR
    process.env.NO_COLOR = '1'
    expect(renderHelp('secrets')).not.toMatch(/\u001B\[/)
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined)
        delete process.env[key]
      else
        process.env[key] = value
    }
  }
})
