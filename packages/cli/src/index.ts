#!/usr/bin/env node
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { parse } from '@bomb.sh/args'
import { cancel, intro, isCancel, log, outro, select } from '@clack/prompts'
import { config } from './commands/config'
import { reset } from './commands/reset'
import { setup } from './commands/setup'

function getVersion(): string {
  const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf-8'))
  return pkg.version
}

const HELP = `n8n-starter

Usage:
  n8n-starter [command] [options]

Commands:
  setup        Generate .env files from .env.template files
  reset        Delete all generated .env files
  config       Configure DOMAIN, AI_RUNTIME and N8N_VARIANT in the root .env file
  hello        Run the interactive example prompt

Options:
  -h, --help     Show this help message
  -v, --version  Show the version number
`

async function hello() {
  intro('n8n-starter')

  const action = await select({
    message: 'What would you like to do?',
    options: [
      { value: 'greet', label: 'Print a greeting' },
      { value: 'exit', label: 'Exit' },
    ],
  })

  if (isCancel(action)) {
    cancel('Operation cancelled.')
    return
  }

  if (action === 'greet') {
    log.success('Hello from n8n-starter!')
  }

  outro('Done.')
}

export async function run(argv: string[]) {
  const args = parse(argv, {
    boolean: ['help', 'version'],
    alias: { h: 'help', v: 'version' },
  })

  const [command] = args._

  if (args.version) {
    console.log(getVersion())
    return
  }

  if (args.help || command === undefined || command === 'help') {
    console.log(HELP)
    return
  }

  switch (command) {
    case 'setup':
      await setup()
      break
    case 'reset':
      await reset()
      break
    case 'config':
      await config()
      break
    case 'hello':
      await hello()
      break
    default:
      console.error(`Unknown command: ${command}\n`)
      console.log(HELP)
      process.exitCode = 1
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  run(process.argv.slice(2))
}
