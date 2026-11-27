#!/usr/bin/env node
// The compose lint gate: dclint, env interpolation, healthchecks, compose-lint.
//   node lint.mjs                                 the gate
//   node lint.mjs --fix                           compose-lint fix as a dry-run diff, then dclint --fix
//   node lint.mjs --fix --apply [--only CL-0003]  write the compose-lint fixes, optionally for given rules only
// Rules and reasoning: see ../SPEC.md (compose spec rules).
import { spawnSync } from 'node:child_process'
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, relative } from 'node:path'

const composeDir = import.meta.dirname
const COMPOSE_LINT_IMAGE = 'composelint/compose-lint:1.8.2'

const args = process.argv.slice(2)
const fix = args.includes('--fix')
const apply = args.includes('--apply')
const only = args.flatMap((arg, i) => (arg === '--only' ? [args[i + 1]] : []))
if ((apply || only.length > 0) && !fix) {
  console.error('--apply and --only need --fix')
  process.exit(2)
}
if (only.some((rule) => !/^CL-\d{4}$/.test(rule ?? ''))) {
  console.error('--only takes a compose-lint rule id such as CL-0003')
  process.exit(2)
}

const composeFiles = (function walk(dir) {
  const files = []
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules') continue
    const path = join(dir, entry.name)
    if (entry.isDirectory()) files.push(...walk(path))
    else if (/^docker-compose.*\.yml$/.test(entry.name)) files.push(relative(composeDir, path))
  }
  return files.sort()
})(composeDir)

function run(command, args, options = {}) {
  return spawnSync(command, args, { cwd: composeDir, stdio: 'inherit', ...options })
}

function dclint() {
  return run(join(composeDir, 'node_modules/.bin/dclint'), ['.', '--recursive', '--max-warnings', '0']).status
}

function dclintFix() {
  return run(join(composeDir, 'node_modules/.bin/dclint'), ['.', '--fix', '--recursive']).status
}

// No bare ${VAR} or $VAR interpolation: every variable carries :- or :? (see ../SPEC.md).
function lintEnv() {
  const bare = /(^|[^$])\$(\{[A-Za-z_][A-Za-z0-9_]*\}|[A-Za-z_])/
  let status = 0
  for (const file of composeFiles) {
    const lines = readFileSync(join(composeDir, file), 'utf8').split('\n')
    lines.forEach((line, i) => {
      if (bare.test(line)) {
        console.error(`${file}:${i + 1}: bare interpolation: ${line.trim()}`)
        status = 1
      }
    })
  }
  return status
}

// Every long-running service has a healthcheck; a service another one awaits with
// service_completed_successfully runs once and is exempt (see ../SPEC.md).
function lintHealthcheck() {
  let status = 0
  for (const file of composeFiles) {
    const result = run('docker', ['compose', '-f', file, '--profile', '*', 'config', '--no-interpolate', '--format', 'json'], { stdio: ['ignore', 'pipe', 'inherit'] })
    if (result.status !== 0) {
      console.error(`${file}: docker compose config failed`)
      status = 1
      continue
    }
    const services = JSON.parse(result.stdout.toString()).services ?? {}
    const runsOnce = new Set()
    for (const service of Object.values(services)) {
      for (const [dependency, spec] of Object.entries(service.depends_on ?? {})) {
        if (spec?.condition === 'service_completed_successfully') runsOnce.add(dependency)
      }
    }
    const missing = Object.entries(services)
      .filter(([name]) => !runsOnce.has(name))
      .filter(([, service]) => {
        const healthcheck = service.healthcheck ?? {}
        const test = healthcheck.test ?? []
        return healthcheck.disable === true || test.length === 0 || (test.length === 1 && test[0] === 'NONE')
      })
      .map(([name]) => name)
    if (missing.length > 0) {
      console.error(`${file}: no healthcheck: ${missing.join(', ')}`)
      status = 1
    }
  }
  return status
}

// Security lint with the baseline in .compose-lint.yml (see ../SPEC.md).
function composeLint() {
  return run('docker', ['run', '--rm', '-v', `${composeDir}:/src`, COMPOSE_LINT_IMAGE, ...composeFiles]).status
}

// compose-lint fix never touches a suppressed finding and the baseline suppresses every
// finding that predates the gate, so it runs against an empty config: the baseline is the
// backlog to fix. A dry run (a diff on stdout, a read-only mount) unless --apply; fixes such as
// read_only are behavior-changing, hence --only. Remove the baseline entries of what was fixed.
function composeLintFix() {
  const dir = mkdtempSync(join(tmpdir(), 'compose-lint-'))
  try {
    const config = join(dir, 'empty.yml')
    writeFileSync(config, 'rules: {}\n')
    const user = apply && process.getuid ? ['--user', `${process.getuid()}:${process.getgid()}`] : []
    return run('docker', [
      'run', '--rm', ...user,
      '-v', `${composeDir}:/src${apply ? '' : ':ro'}`,
      '-v', `${config}:/empty.yml:ro`,
      COMPOSE_LINT_IMAGE, 'fix', '--config', '/empty.yml',
      ...(apply ? ['--apply'] : []),
      ...only.flatMap((rule) => ['--only', rule]),
      ...composeFiles,
    ]).status ?? 1
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
}

// compose-lint inserts keys at the top of a service: dclint --fix runs last to restore the key order.
const stages = fix
  ? [
      [apply ? 'compose-lint fix --apply' : 'compose-lint fix (dry run)', composeLintFix],
      ['dclint --fix', dclintFix],
    ]
  : [
      ['dclint', dclint],
      ['lint:env', lintEnv],
      ['lint:healthcheck', lintHealthcheck],
      ['compose-lint', composeLint],
    ]

const failed = []
for (const [name, stage] of stages) {
  const status = stage() ?? 1
  console.error(`${name}: ${status === 0 ? 'ok' : `failed (exit ${status})`}`)
  if (status !== 0) failed.push(name)
}
if (failed.length > 0) {
  console.error(`${fix ? 'lint:fix' : 'lint'} failed: ${failed.join(', ')}`)
  process.exitCode = 1
}
