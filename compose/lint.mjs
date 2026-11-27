#!/usr/bin/env node
// The compose lint gate: dclint, env interpolation, healthchecks, compose-lint.
// Rules and reasoning: see ../SPEC.md (compose spec rules).
import { spawnSync } from 'node:child_process'
import { readdirSync, readFileSync } from 'node:fs'
import { join, relative } from 'node:path'

const composeDir = import.meta.dirname
const COMPOSE_LINT_IMAGE = 'composelint/compose-lint:1.8.2'

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

if (process.argv.includes('--fix')) {
  process.exit(dclintFix() ?? 1)
}

const stages = [
  ['dclint', dclint],
  ['lint:env', lintEnv],
  ['lint:healthcheck', lintHealthcheck],
  ['compose-lint', composeLint],
]

const failed = []
for (const [name, stage] of stages) {
  const status = stage()
  console.error(`${name}: ${status === 0 ? 'ok' : `failed (exit ${status})`}`)
  if (status !== 0) failed.push(name)
}
if (failed.length > 0) {
  console.error(`lint failed: ${failed.join(', ')}`)
  process.exitCode = 1
}
