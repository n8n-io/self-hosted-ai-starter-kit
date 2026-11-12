import type { Config } from '../schemas/config'
import type { GenerateSecret, LinkSecret, PromptSecret, SecretEntry, SecretRequired } from '../schemas/secrets'
import { randomBytes } from 'node:crypto'
import { readFile, writeFile } from 'node:fs/promises'
import { dirname, join, relative, resolve } from 'node:path'
import { isCancel, password } from '@clack/prompts'
import { z } from 'zod'
import { secretsManifestSchema } from '../schemas/secrets'
import { parseEnvContent, updateEnvContent } from '../utils/env'
import { findFiles } from '../utils/files'
import { keyValue, runCommand } from '../utils/format'
import { logger } from '../utils/logger'
import { readRootConfig } from './tilt'

export const MANIFEST_FILENAME = '.env.secrets.json'
const TEMPLATE_FILENAME = '.env.template'
const ENV_FILENAME = '.env'

export const SECRETS_SUBCOMMANDS = ['read', 'set'] as const

/** One key of a .env.secrets.json, with the directory whose .env.template and .env hold it */
export interface DeclaredSecret {
  dir: string
  key: string
  entry: SecretEntry
}

export type DeclaredLink = DeclaredSecret & { entry: LinkSecret }

/** A directory with a manifest: its .env (content undefined until `setup` created it) and its .env.template values */
export interface SecretDirectory {
  dir: string
  envPath: string
  envContent?: string
  env: Record<string, string>
  template: Record<string, string>
}

export interface SecretState {
  rootDir: string
  declared: DeclaredSecret[]
  directories: Map<string, SecretDirectory>
}

export type SecretStatus = 'ok' | 'unset' | 'missing' | 'mismatch' | 'required'

export interface SecretCheck {
  envPath: string
  key: string
  status: SecretStatus
  /** The .env and key a link copies from */
  source?: { envPath: string, key: string }
  /** The root .env condition a required prompt secret is missing for, such as N8N_VARIANT=enterprise */
  condition?: string
}

/** The statuses that fail `verify` */
export const FAILED_SECRET_STATUSES: SecretStatus[] = ['missing', 'mismatch', 'required']

export interface SecretWriteResult {
  envPath: string
  key: string
  status: 'generated' | 'linked' | 'set'
}

export interface SecretValue {
  envPath: string
  key: string
  value: string | undefined
  source: SecretEntry['source']
}

function isLink(secret: DeclaredSecret): secret is DeclaredLink {
  return secret.entry.source === 'link'
}

async function readOptionalFile(path: string): Promise<string | undefined> {
  try {
    return await readFile(path, 'utf-8')
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT')
      throw error
    return undefined
  }
}

/** The declaration a link copies from; readSecretManifests guarantees it exists and is not a link itself */
export function linkSource(link: DeclaredLink, declared: DeclaredSecret[]): DeclaredSecret {
  const dir = resolve(link.dir, link.entry.from)
  return declared.find(candidate => candidate.dir === dir && candidate.key === link.entry.key)!
}

/**
 * Every key of every .env.secrets.json under rootDir, validated, with every link resolved to a generate
 * or prompt entry of another manifest. Throws naming the manifest on the first problem.
 */
export async function readSecretManifests(rootDir: string): Promise<DeclaredSecret[]> {
  const declared: DeclaredSecret[] = []
  for (const file of await findFiles(rootDir, MANIFEST_FILENAME)) {
    let json: unknown
    try {
      json = JSON.parse(await readFile(file, 'utf-8'))
    } catch (error) {
      throw new Error(`Invalid ${file}: ${(error as Error).message}`)
    }
    const result = secretsManifestSchema.safeParse(json)
    if (!result.success)
      throw new Error(`Invalid ${file}:\n${z.prettifyError(result.error)}`)
    for (const [key, entry] of Object.entries(result.data.secrets))
      declared.push({ dir: dirname(file), key, entry })
  }
  for (const secret of declared) {
    if (!isLink(secret))
      continue
    const target = resolve(secret.dir, secret.entry.from)
    const source = declared.find(candidate => candidate.dir === target && candidate.key === secret.entry.key)
    const link = `${join(relative(rootDir, secret.dir), MANIFEST_FILENAME)}: ${secret.key} links to ${secret.entry.key} of ${relative(rootDir, target) || '.'}`
    if (source === undefined)
      throw new Error(`Invalid ${link}, which no ${MANIFEST_FILENAME} declares`)
    if (isLink(source))
      throw new Error(`Invalid ${link}, which is a link itself`)
  }
  return declared
}

/** The manifests with the .env and .env.template values of their directories */
export async function readSecretState(rootDir: string): Promise<SecretState> {
  const declared = await readSecretManifests(rootDir)
  const directories = new Map<string, SecretDirectory>()
  for (const dir of new Set(declared.map(secret => secret.dir))) {
    const template = await readOptionalFile(join(dir, TEMPLATE_FILENAME))
    if (template === undefined)
      throw new Error(`No ${TEMPLATE_FILENAME} next to ${join(relative(rootDir, dir), MANIFEST_FILENAME)}`)
    const envPath = join(dir, ENV_FILENAME)
    const envContent = await readOptionalFile(envPath)
    directories.set(dir, { dir, envPath, envContent, env: envContent === undefined ? {} : parseEnvContent(envContent), template: parseEnvContent(template) })
  }
  return { rootDir, declared, directories }
}

/** A secret is unfilled while it is absent, empty or still the value of its template (the placeholder a copied template leaves behind) */
export function isUnfilled(value: string | undefined, templateValue: string | undefined): boolean {
  return value === undefined || value === '' || value === templateValue
}

export function generateSecret(entry: GenerateSecret): string {
  return entry.prefix + randomBytes(entry.bytes).toString(entry.encoding)
}

/** The root .env condition a prompt secret is required under right now, such as `N8N_VARIANT=enterprise`, or undefined while it is optional */
export function requiredBy(entry: PromptSecret, config: Config): string | undefined {
  if (entry.required === undefined)
    return undefined
  const conditions = (Object.entries(entry.required) as [keyof SecretRequired, string[] | undefined][]).filter(([, values]) => values !== undefined)
  const matched = conditions.every(([key, values]) => values!.includes(config[key]))
  return matched ? conditions.map(([key]) => `${key}=${config[key]}`).join(', ') : undefined
}

/**
 * The state of every declared secret of a directory that has a .env (a missing .env is reported by itself);
 * the conditions of prompt secrets need the root config and are skipped without it.
 */
export function checkSecrets(state: SecretState, config?: Config): SecretCheck[] {
  const checks: SecretCheck[] = []
  for (const secret of state.declared) {
    const directory = state.directories.get(secret.dir)!
    if (directory.envContent === undefined)
      continue
    const { envPath, env, template } = directory
    const { key, entry } = secret
    const unfilled = isUnfilled(env[key], template[key])
    if (entry.source === 'generate') {
      checks.push({ envPath, key, status: unfilled ? 'missing' : 'ok' })
    } else if (entry.source === 'link') {
      const source = linkSource({ ...secret, entry }, state.declared)
      const sourceDirectory = state.directories.get(source.dir)!
      const sourceValue = sourceDirectory.env[source.key]
      const sourceFilled = !isUnfilled(sourceValue, sourceDirectory.template[source.key])
      const status = unfilled ? 'missing' : sourceFilled && env[key] !== sourceValue ? 'mismatch' : 'ok'
      checks.push({ envPath, key, status, source: { envPath: sourceDirectory.envPath, key: source.key } })
    } else {
      const condition = config === undefined ? undefined : requiredBy(entry, config)
      const status = !unfilled ? 'ok' : condition === undefined ? 'unset' : 'required'
      checks.push({ envPath, key, status, ...(condition === undefined ? {} : { condition }) })
    }
  }
  return checks
}

/** One line per check, the failed ones naming the command that fixes them */
export function formatSecretCheck(rootDir: string, check: SecretCheck): string {
  const path = relative(rootDir, check.envPath)
  switch (check.status) {
    case 'missing':
      return `Missing secret ${check.key} in ${path}`
    case 'mismatch':
      return `${check.key} in ${path} differs from ${check.source!.key} in ${relative(rootDir, check.source!.envPath)}`
    case 'required':
      return `${check.key} in ${path} is required for ${check.condition}, run ${runCommand(`secrets set ${check.key}`)}`
    case 'unset':
      return `Secret ${check.key} not set in ${path} (optional)`
    default:
      return `Secret ${check.key} set in ${path}`
  }
}

/** Queues a value for its .env and makes it visible to the passes that follow */
function queue(updates: Map<string, Record<string, string>>, directory: SecretDirectory, key: string, value: string) {
  directory.env[key] = value
  updates.set(directory.dir, { ...updates.get(directory.dir), [key]: value })
}

/** Writes the queued values into their .env files, comments and other keys preserved, and keeps the state in sync */
async function applyUpdates(state: SecretState, updates: Map<string, Record<string, string>>) {
  for (const [dir, values] of updates) {
    const directory = state.directories.get(dir)!
    directory.envContent = updateEnvContent(directory.envContent!, values)
    await writeFile(directory.envPath, directory.envContent)
  }
}

/**
 * Fills the .env files: every unfilled generate secret gets a random value once, then every link is set to
 * its source (always, so a source set by hand propagates). Prompt secrets, filled values and directories
 * without a .env are left alone, so re-running changes nothing (see ../../../../SPEC.md).
 */
export async function fillSecrets(rootDir: string): Promise<SecretWriteResult[]> {
  const state = await readSecretState(rootDir)
  const updates = new Map<string, Record<string, string>>()
  const results: SecretWriteResult[] = []
  for (const secret of state.declared) {
    const directory = state.directories.get(secret.dir)!
    if (secret.entry.source !== 'generate' || directory.envContent === undefined)
      continue
    if (isUnfilled(directory.env[secret.key], directory.template[secret.key])) {
      queue(updates, directory, secret.key, generateSecret(secret.entry))
      results.push({ envPath: directory.envPath, key: secret.key, status: 'generated' })
    }
  }
  for (const secret of state.declared) {
    const directory = state.directories.get(secret.dir)!
    if (!isLink(secret) || directory.envContent === undefined)
      continue
    const source = linkSource(secret, state.declared)
    const sourceDirectory = state.directories.get(source.dir)!
    const value = sourceDirectory.env[source.key]
    if (value === undefined || isUnfilled(value, sourceDirectory.template[source.key]) || directory.env[secret.key] === value)
      continue
    queue(updates, directory, secret.key, value)
    results.push({ envPath: directory.envPath, key: secret.key, status: 'linked' })
  }
  await applyUpdates(state, updates)
  return results
}

/** The declared secrets with their current values, keeping those whose directory or key contains `filter` (case-insensitive) */
export function listSecrets(state: SecretState, filter = ''): SecretValue[] {
  const needle = filter.toLowerCase()
  return state.declared
    .filter(secret => relative(state.rootDir, secret.dir).toLowerCase().includes(needle) || secret.key.toLowerCase().includes(needle))
    .map((secret) => {
      const directory = state.directories.get(secret.dir)!
      return { envPath: directory.envPath, key: secret.key, value: directory.env[secret.key], source: secret.entry.source }
    })
}

/** Writes `value` to every directory declaring `key` as generate or prompt, then to every link of it */
export async function setSecret(state: SecretState, key: string, value: string): Promise<SecretWriteResult[]> {
  const targets = state.declared.filter(secret => secret.key === key && !isLink(secret))
  if (targets.length === 0)
    throw new Error(`Unknown secret "${key}"`)
  const updates = new Map<string, Record<string, string>>()
  const results: SecretWriteResult[] = []
  for (const target of targets) {
    const directory = state.directories.get(target.dir)!
    if (directory.envContent === undefined)
      throw new Error(`No ${relative(state.rootDir, directory.envPath)} file found. Run ${runCommand('setup')} first.`)
    queue(updates, directory, key, value)
    results.push({ envPath: directory.envPath, key, status: 'set' })
  }
  for (const secret of state.declared) {
    if (!isLink(secret) || !targets.includes(linkSource(secret, state.declared)))
      continue
    const directory = state.directories.get(secret.dir)!
    if (directory.envContent === undefined || directory.env[secret.key] === value)
      continue
    queue(updates, directory, secret.key, value)
    results.push({ envPath: directory.envPath, key: secret.key, status: 'linked' })
  }
  await applyUpdates(state, updates)
  return results
}

/** The root config the prompt conditions are checked against; undefined while the root .env is missing or invalid, which verify and tilt resources report */
export async function readRootConfigIfValid(rootDir: string): Promise<Config | undefined> {
  try {
    return await readRootConfig(rootDir)
  } catch {
    return undefined
  }
}

/**
 * `secrets read [filter] [--json]`: the declared secrets and their values on stdout, nothing else; grouped
 * by .env with the keys in cyan on a tty, only the value when the filter is an exact key (so it can be piped),
 * or with `json` one array of `{ file, key, value, source }` (`value` null while the key is absent from the .env)
 */
async function read(rootDir: string, filter: string | undefined, json: boolean): Promise<void> {
  const state = await readSecretState(rootDir)
  const exact = filter !== undefined && state.declared.some(secret => secret.key === filter.toUpperCase()) ? filter.toUpperCase() : undefined
  const matches = exact === undefined ? listSecrets(state, filter) : listSecrets(state, exact).filter(secret => secret.key === exact)
  if (matches.length === 0)
    throw new Error(filter === undefined ? `No ${MANIFEST_FILENAME} found in ${rootDir}` : `No secret matches "${filter}", run ${runCommand('secrets read')} for the list`)
  for (const envPath of new Set(matches.map(match => match.envPath))) {
    if (state.directories.get(dirname(envPath))!.envContent === undefined)
      throw new Error(`No ${relative(rootDir, envPath)} file found. Run ${runCommand('setup')} first.`)
  }
  if (json) {
    console.log(JSON.stringify(matches.map(({ envPath, key, value, source }) => ({ file: relative(rootDir, envPath), key, value: value ?? null, source })), null, 2))
    return
  }
  if (exact !== undefined) {
    for (const match of matches)
      console.log(match.value ?? '')
    return
  }
  const lines: string[] = []
  let current: string | undefined
  for (const match of matches) {
    if (match.envPath !== current) {
      if (current !== undefined)
        lines.push('')
      lines.push(relative(rootDir, match.envPath))
      current = match.envPath
    }
    lines.push(keyValue(match.key, match.value ?? ''))
  }
  console.log(lines.join('\n'))
}

/**
 * `secrets set KEY [value]`: writes one generate or prompt secret, asked for with a masked prompt when no
 * value is given, then copies it to its links. A link key is refused with a pointer to its source.
 */
async function set(rootDir: string, key: string | undefined, value: string | undefined): Promise<void> {
  logger.intro('n8n-starter secrets set')

  const state = await readSecretState(rootDir)
  const names = [...new Set(state.declared.filter(secret => !isLink(secret)).map(secret => secret.key))].join(', ')
  if (key === undefined) {
    logger.error(`Missing secret key. Expected one of: ${names}`)
    process.exitCode = 1
    return
  }
  const targets = state.declared.filter(secret => secret.key === key && !isLink(secret))
  if (targets.length === 0) {
    const link = state.declared.find(secret => secret.key === key && isLink(secret)) as DeclaredLink | undefined
    if (link === undefined) {
      logger.error(`Unknown secret "${key}". Expected one of: ${names}`)
    } else {
      const source = linkSource(link, state.declared)
      logger.error(`${key} is a copy of ${source.key} in ${relative(rootDir, join(source.dir, ENV_FILENAME))}, run ${runCommand(`secrets set ${source.key}`)}`)
    }
    process.exitCode = 1
    return
  }
  for (const target of targets) {
    const directory = state.directories.get(target.dir)!
    if (directory.envContent === undefined) {
      logger.error(`No ${relative(rootDir, directory.envPath)} file found. Run ${runCommand('setup')} first.`)
      process.exitCode = 1
      return
    }
  }

  let resolved = value
  if (resolved === undefined) {
    const entered = await password({
      message: (targets[0]!.entry as GenerateSecret | PromptSecret).description,
      validate: entered => (entered ?? '').length > 0 ? undefined : 'The value must not be empty',
    })
    if (isCancel(entered)) {
      logger.cancel('Secret not changed.')
      return
    }
    resolved = entered
  } else if (resolved === '') {
    logger.error(`Invalid ${key}: the value must not be empty`)
    process.exitCode = 1
    return
  }

  for (const target of targets) {
    const directory = state.directories.get(target.dir)!
    if (target.entry.source === 'generate' && target.entry.rotation === 'never' && !isUnfilled(directory.env[key], directory.template[key]))
      logger.warn(`${key} in ${relative(rootDir, directory.envPath)} is already set and the data in .volumes/ depends on it`)
  }

  for (const { envPath, key: written, status } of await setSecret(state, key, resolved))
    logger.success(`${written} ${status === 'set' ? 'set' : 'linked'} in ${relative(rootDir, envPath)}`)
  logger.outro('Secret written.')
}

/** `secrets <read|set> [value] [--json]`, see ../../README.md */
export async function secrets(rootDir = process.cwd(), [subcommand, key, value]: string[] = [], { json = false }: { json?: boolean } = {}) {
  if (subcommand !== 'read' && subcommand !== 'set') {
    logger.error(`${subcommand === undefined ? 'Missing' : 'Unknown'} sub-command${subcommand === undefined ? '' : ` "${subcommand}"`} for secrets. Expected one of: ${SECRETS_SUBCOMMANDS.join(', ')}`)
    process.exitCode = 1
    return
  }
  try {
    if (subcommand === 'read')
      await read(rootDir, key, json)
    else
      await set(rootDir, key, value)
  } catch (error) {
    // a missing .env, an invalid manifest or an unresolvable link names the file
    logger.error((error as Error).message)
    process.exitCode = 1
  }
}
