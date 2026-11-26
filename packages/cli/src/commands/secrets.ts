import type { Config } from '../schemas/config'
import type { GenerateSecret, LinkSecret, PromptSecret, SecretEntry, SecretRequired } from '../schemas/secrets'
import type { DerivedGenerator } from '../utils/generators'
import { readFile, writeFile } from 'node:fs/promises'
import { dirname, join, relative, resolve, sep } from 'node:path'
import { isCancel, password } from '@clack/prompts'
import { z } from 'zod'
import { secretsManifestSchema } from '../schemas/secrets'
import { formatEnvValue, parseEnvContent, parseEnvDefaults, updateEnvContent } from '../utils/env'
import { findFiles } from '../utils/files'
import { keyValue, runCommand } from '../utils/format'
import { derive, generateRandom, isDerived, isDerivedFrom } from '../utils/generators'
import { logger } from '../utils/logger'
import { readRootConfig } from './tilt'

export const MANIFEST_FILENAME = '.env.json'
/** Beside a .env: the secrets no container reads, kept for humans and as the input of derived values (`file` of a manifest entry) */
export const SECRETS_FILENAME = '.env.secrets'
const TEMPLATE_FILENAME = '.env.template'
const ENV_FILENAME = '.env'
/** The first line of a .env.secrets the CLI creates */
const SECRETS_HEADER = `# secrets no container reads, written by ${runCommand('setup')} and ${runCommand('secrets set')}, see ./${MANIFEST_FILENAME}\n`

export const SECRETS_SUBCOMMANDS = ['read', 'set'] as const

/** One key of a .env.json, with the directory whose .env or .env.secrets holds it */
export interface DeclaredSecret {
  dir: string
  key: string
  entry: SecretEntry
}

export type DeclaredLink = DeclaredSecret & { entry: LinkSecret }

/** A generate secret built from another key of its manifest, such as the bcrypt hash of a password */
export type DeclaredDerived = DeclaredSecret & { entry: GenerateSecret & { generator: DerivedGenerator } }

/**
 * A directory with a manifest: its .env (content undefined until `setup` created it), its .env.secrets (content
 * undefined until a secret is written there), its .env.template values and the defaults the template shows commented out
 */
export interface SecretDirectory {
  dir: string
  envPath: string
  envContent?: string
  env: Record<string, string>
  secretsPath: string
  secretsContent?: string
  secrets: Record<string, string>
  template: Record<string, string>
  defaults: Record<string, string>
}

export interface SecretState {
  rootDir: string
  declared: DeclaredSecret[]
  directories: Map<string, SecretDirectory>
}

export type SecretStatus = 'ok' | 'unset' | 'missing' | 'mismatch' | 'required'

export interface SecretCheck {
  /** The file that holds the key: the .env, or the .env.secrets beside it */
  envPath: string
  key: string
  status: SecretStatus
  /** The file and key a link copies from or a derived value is built from */
  source?: { envPath: string, key: string }
  /** Set on a derived value, whose mismatch is no difference but a hash that does not fit its input */
  derived?: boolean
  /** The root .env condition a required prompt secret or a conditional link is missing for, such as N8N_VARIANT=enterprise */
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
  /** Set on a derived value, which `secrets read` lists only when it is named */
  derived?: boolean
  /** The keys the entry names as `related`, with their value of the .env or the default of the template */
  related?: Record<string, string | undefined>
}

/** The queued values per file path */
type Updates = Map<string, Record<string, string>>

function isLink(secret: DeclaredSecret): secret is DeclaredLink {
  return secret.entry.source === 'link'
}

export function isDerivedSecret(secret: DeclaredSecret): secret is DeclaredDerived {
  return secret.entry.source === 'generate' && isDerived(secret.entry.generator)
}

function inSecretsFile(entry: SecretEntry): boolean {
  return entry.source === 'generate' && entry.file === SECRETS_FILENAME
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

/** The file a declared secret lives in: the .env compose reads, or the .env.secrets beside it */
export function secretPath(state: SecretState, secret: DeclaredSecret): string {
  const directory = state.directories.get(secret.dir)!
  return inSecretsFile(secret.entry) ? directory.secretsPath : directory.envPath
}

function secretValues(state: SecretState, secret: DeclaredSecret): Record<string, string> {
  const directory = state.directories.get(secret.dir)!
  return inSecretsFile(secret.entry) ? directory.secrets : directory.env
}

export function secretValue(state: SecretState, secret: DeclaredSecret): string | undefined {
  return secretValues(state, secret)[secret.key]
}

/** The declaration a link copies from; readSecretManifests guarantees it exists and is not a link itself */
export function linkSource(link: DeclaredLink, declared: DeclaredSecret[]): DeclaredSecret {
  const dir = resolve(link.dir, link.entry.from)
  return declared.find(candidate => candidate.dir === dir && candidate.key === link.entry.key)!
}

/** The declaration a derived value is built from; readSecretManifests guarantees it is a random generate entry of the same manifest */
export function derivedInput(derived: DeclaredDerived, declared: DeclaredSecret[]): DeclaredSecret {
  return declared.find(candidate => candidate.dir === derived.dir && candidate.key === derived.entry.generator.input)!
}

/**
 * Every key of every .env.json under rootDir, validated, with every link resolved to a generate or prompt entry
 * of another manifest and every generator input to a random generate entry of the same one. Throws naming the
 * manifest on the first problem.
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
    const manifest = join(relative(rootDir, secret.dir), MANIFEST_FILENAME)
    if (isLink(secret)) {
      const target = resolve(secret.dir, secret.entry.from)
      const source = declared.find(candidate => candidate.dir === target && candidate.key === secret.entry.key)
      const link = `${manifest}: ${secret.key} links to ${secret.entry.key} of ${relative(rootDir, target) || '.'}`
      if (source === undefined)
        throw new Error(`Invalid ${link}, which no ${MANIFEST_FILENAME} declares`)
      if (isLink(source))
        throw new Error(`Invalid ${link}, which is a link itself`)
    } else if (isDerivedSecret(secret)) {
      const input = derivedInput(secret, declared) as DeclaredSecret | undefined
      const derived = `${manifest}: ${secret.key} is derived from ${secret.entry.generator.input}`
      if (input === undefined)
        throw new Error(`Invalid ${derived}, which the manifest does not declare`)
      if (input.entry.source !== 'generate' || isDerived(input.entry.generator))
        throw new Error(`Invalid ${derived}, which is not a random generate entry`)
    }
  }
  return declared
}

/** The manifests with the .env, .env.secrets and .env.template values of their directories */
export async function readSecretState(rootDir: string): Promise<SecretState> {
  const declared = await readSecretManifests(rootDir)
  const directories = new Map<string, SecretDirectory>()
  for (const dir of new Set(declared.map(secret => secret.dir))) {
    const template = await readOptionalFile(join(dir, TEMPLATE_FILENAME))
    if (template === undefined)
      throw new Error(`No ${TEMPLATE_FILENAME} next to ${join(relative(rootDir, dir), MANIFEST_FILENAME)}`)
    const envPath = join(dir, ENV_FILENAME)
    const envContent = await readOptionalFile(envPath)
    const secretsPath = join(dir, SECRETS_FILENAME)
    const secretsContent = await readOptionalFile(secretsPath)
    directories.set(dir, {
      dir,
      envPath,
      envContent,
      env: envContent === undefined ? {} : parseEnvContent(envContent),
      secretsPath,
      secretsContent,
      secrets: secretsContent === undefined ? {} : parseEnvContent(secretsContent),
      template: parseEnvContent(template),
      defaults: parseEnvDefaults(template),
    })
  }
  return { rootDir, declared, directories }
}

/** A secret is unfilled while it is absent, empty or still the value of its template (the placeholder a copied template leaves behind) */
export function isUnfilled(value: string | undefined, templateValue: string | undefined): boolean {
  return value === undefined || value === '' || value === templateValue
}

/** isUnfilled for a declared secret in the file it lives in; a .env.secrets key has no template value */
export function isSecretUnfilled(state: SecretState, secret: DeclaredSecret): boolean {
  const templateValue = inSecretsFile(secret.entry) ? undefined : state.directories.get(secret.dir)!.template[secret.key]
  return isUnfilled(secretValue(state, secret), templateValue)
}

/**
 * The root .env condition a prompt secret or a conditional link is required under right now, such as
 * `N8N_VARIANT=enterprise`, or undefined while it is optional
 */
export function requiredBy(entry: PromptSecret | LinkSecret, config: Config): string | undefined {
  if (entry.required === undefined)
    return undefined
  const conditions = (Object.entries(entry.required) as [keyof SecretRequired, string[] | undefined][]).filter(([, values]) => values !== undefined)
  const matched = conditions.every(([key, values]) => values!.includes(config[key]))
  return matched ? conditions.map(([key]) => `${key}=${config[key]}`).join(', ') : undefined
}

/**
 * The state of every declared secret of a directory that has a .env (a missing .env is reported by itself);
 * the conditions of prompt secrets need the root config and are skipped without it. A link with a condition is
 * missing only while the root config meets it: without one, or without the root config, an unfilled one is unset.
 */
export function checkSecrets(state: SecretState, config?: Config): SecretCheck[] {
  const checks: SecretCheck[] = []
  for (const secret of state.declared) {
    if (state.directories.get(secret.dir)!.envContent === undefined)
      continue
    const { key, entry } = secret
    const envPath = secretPath(state, secret)
    const unfilled = isSecretUnfilled(state, secret)
    if (isDerivedSecret(secret)) {
      const input = derivedInput(secret, state.declared)
      const fits = isSecretUnfilled(state, input) || isDerivedFrom(secret.entry.generator, secretValue(state, input)!, secretValue(state, secret) ?? '')
      checks.push({ envPath, key, status: unfilled ? 'missing' : fits ? 'ok' : 'mismatch', source: { envPath: secretPath(state, input), key: input.key }, derived: true })
    } else if (entry.source === 'generate') {
      checks.push({ envPath, key, status: unfilled ? 'missing' : 'ok' })
    } else if (isLink(secret)) {
      const source = linkSource(secret, state.declared)
      const sourceFilled = !isSecretUnfilled(state, source)
      const conditional = secret.entry.required !== undefined
      const condition = conditional && config !== undefined ? requiredBy(secret.entry, config) : undefined
      const status = unfilled ? conditional && condition === undefined ? 'unset' : 'missing' : sourceFilled && secretValue(state, secret) !== secretValue(state, source) ? 'mismatch' : 'ok'
      checks.push({ envPath, key, status, source: { envPath: secretPath(state, source), key: source.key }, ...(condition === undefined ? {} : { condition }) })
    } else {
      const condition = config === undefined ? undefined : requiredBy(entry as PromptSecret, config)
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
      return `Missing secret ${check.key} in ${path}${check.condition === undefined ? '' : `, required for ${check.condition}`}`
    case 'mismatch':
      return `${check.key} in ${path} ${check.derived ? 'does not match' : 'differs from'} ${check.source!.key} in ${relative(rootDir, check.source!.envPath)}`
    case 'required':
      return `${check.key} in ${path} is required for ${check.condition}, run ${runCommand(`secrets set ${check.key}`)}`
    case 'unset':
      return `Secret ${check.key} not set in ${path} (optional)`
    default:
      return `Secret ${check.key} set in ${path}`
  }
}

/** Queues a value for the file its secret lives in and makes it visible to the passes that follow */
function queue(updates: Updates, state: SecretState, secret: DeclaredSecret, value: string) {
  secretValues(state, secret)[secret.key] = value
  const path = secretPath(state, secret)
  updates.set(path, { ...updates.get(path), [secret.key]: value })
}

/**
 * Writes the queued values into their files, comments and other keys preserved, and keeps the state in sync;
 * a .env.secrets is created on its first value, readable by its owner only
 */
async function applyUpdates(state: SecretState, updates: Updates) {
  for (const [path, values] of updates) {
    const directory = state.directories.get(dirname(path))!
    if (path === directory.secretsPath) {
      directory.secretsContent = updateEnvContent(directory.secretsContent ?? SECRETS_HEADER, values)
      await writeFile(path, directory.secretsContent, { mode: 0o600 })
    } else {
      directory.envContent = updateEnvContent(directory.envContent!, values)
      await writeFile(path, directory.envContent)
    }
  }
}

/**
 * The value a derived secret needs now, or undefined while its input is unfilled or it already fits: a salted
 * hash is new on every run, so it is only rewritten when it is empty or no longer the hash of its input
 */
function staleDerived(state: SecretState, secret: DeclaredDerived): string | undefined {
  const input = derivedInput(secret, state.declared)
  if (isSecretUnfilled(state, input))
    return undefined
  const inputValue = secretValue(state, input)!
  if (!isSecretUnfilled(state, secret) && isDerivedFrom(secret.entry.generator, inputValue, secretValue(state, secret)!))
    return undefined
  return derive(secret.entry.generator, inputValue)
}

/**
 * Fills the .env and .env.secrets files: every unfilled random secret gets a value once, then every derived
 * value is set to what its input gives and every link to its source (always, so an input or a source set by
 * hand propagates). Prompt secrets, filled values and directories without a .env are left alone, so re-running
 * changes nothing (see ../../../../SPEC.md).
 */
export async function fillSecrets(rootDir: string): Promise<SecretWriteResult[]> {
  const state = await readSecretState(rootDir)
  const updates: Updates = new Map()
  const results: SecretWriteResult[] = []
  const hasEnv = (secret: DeclaredSecret) => state.directories.get(secret.dir)!.envContent !== undefined
  for (const secret of state.declared) {
    if (secret.entry.source !== 'generate' || isDerived(secret.entry.generator) || !hasEnv(secret))
      continue
    if (isSecretUnfilled(state, secret)) {
      queue(updates, state, secret, generateRandom(secret.entry.generator))
      results.push({ envPath: secretPath(state, secret), key: secret.key, status: 'generated' })
    }
  }
  for (const secret of state.declared) {
    if (!isDerivedSecret(secret) || !hasEnv(secret))
      continue
    const value = staleDerived(state, secret)
    if (value === undefined)
      continue
    queue(updates, state, secret, value)
    results.push({ envPath: secretPath(state, secret), key: secret.key, status: 'generated' })
  }
  for (const secret of state.declared) {
    if (!isLink(secret) || !hasEnv(secret))
      continue
    const source = linkSource(secret, state.declared)
    const value = secretValue(state, source)
    if (value === undefined || isSecretUnfilled(state, source) || secretValue(state, secret) === value)
      continue
    queue(updates, state, secret, value)
    results.push({ envPath: secretPath(state, secret), key: secret.key, status: 'linked' })
  }
  await applyUpdates(state, updates)
  return results
}

/** The value of a related key: what the .env sets, else the live value or the commented default of the template */
function relatedValue(directory: SecretDirectory, key: string): string | undefined {
  return directory.env[key] || directory.template[key] || directory.defaults[key] || undefined
}

/**
 * The declared secrets with their current values, keeping those whose directory or key contains `filter`
 * (case-insensitive). A filter that is the directory of a manifest keeps that directory alone, so the filter of
 * compose/n8n does not list the manifest nested in compose/n8n/assistant.
 */
export function listSecrets(state: SecretState, filter = ''): SecretValue[] {
  const needle = filter.toLowerCase().replace(/\/+$/, '')
  const directory = (secret: DeclaredSecret) => relative(state.rootDir, secret.dir).split(sep).join('/').toLowerCase()
  const exact = needle !== '' && state.declared.some(secret => directory(secret) === needle)
  return state.declared
    .filter(secret => exact ? directory(secret) === needle : directory(secret).includes(needle) || secret.key.toLowerCase().includes(needle))
    .map((secret) => {
      const directory = state.directories.get(secret.dir)!
      const related = secret.entry.source === 'link' ? undefined : secret.entry.related
      return {
        envPath: secretPath(state, secret),
        key: secret.key,
        value: secretValue(state, secret),
        source: secret.entry.source,
        ...(isDerivedSecret(secret) ? { derived: true } : {}),
        ...(related === undefined ? {} : { related: Object.fromEntries(related.map(key => [key, relatedValue(directory, key)])) }),
      }
    })
}

/** A key `secrets set` writes: a link follows its source and a derived value its input */
function isSettable(secret: DeclaredSecret): boolean {
  return !isLink(secret) && !isDerivedSecret(secret)
}

/** Writes `value` to every directory declaring `key` as a settable secret, then to what is derived from it and to every link */
export async function setSecret(state: SecretState, key: string, value: string): Promise<SecretWriteResult[]> {
  const targets = state.declared.filter(secret => secret.key === key && isSettable(secret))
  if (targets.length === 0)
    throw new Error(`Unknown secret "${key}"`)
  const updates: Updates = new Map()
  const results: SecretWriteResult[] = []
  const hasEnv = (secret: DeclaredSecret) => state.directories.get(secret.dir)!.envContent !== undefined
  for (const target of targets) {
    if (!hasEnv(target))
      throw new Error(`No ${relative(state.rootDir, state.directories.get(target.dir)!.envPath)} file found. Run ${runCommand('setup')} first.`)
    queue(updates, state, target, value)
    results.push({ envPath: secretPath(state, target), key, status: 'set' })
  }
  const written = [...targets]
  for (const secret of state.declared) {
    if (!isDerivedSecret(secret) || !targets.includes(derivedInput(secret, state.declared)) || !hasEnv(secret))
      continue
    const derived = staleDerived(state, secret)
    if (derived === undefined)
      continue
    queue(updates, state, secret, derived)
    written.push(secret)
    results.push({ envPath: secretPath(state, secret), key: secret.key, status: 'generated' })
  }
  for (const secret of state.declared) {
    if (!isLink(secret) || !hasEnv(secret))
      continue
    const source = linkSource(secret, state.declared)
    const sourceValue = secretValue(state, source)
    if (!written.includes(source) || sourceValue === undefined || secretValue(state, secret) === sourceValue)
      continue
    queue(updates, state, secret, sourceValue)
    results.push({ envPath: secretPath(state, secret), key: secret.key, status: 'linked' })
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
 * `secrets read [filter] [--json]`: the declared secrets and their values on stdout, nothing else; grouped by
 * the file that holds them with the keys in the accent colour on a tty and the `related` keys of a secret above it, only the
 * value when the filter is an exact key (so it can be piped), or with `json` one array of
 * `{ file, key, value, source, related? }` (`value` null while the key is absent from its file). A derived value
 * is listed only when it is named: a hash is of no use to a reader.
 */
async function read(rootDir: string, filter: string | undefined, json: boolean): Promise<void> {
  const state = await readSecretState(rootDir)
  const exact = filter !== undefined && state.declared.some(secret => secret.key === filter.toUpperCase()) ? filter.toUpperCase() : undefined
  const matches = exact === undefined ? listSecrets(state, filter).filter(secret => !secret.derived) : listSecrets(state, exact).filter(secret => secret.key === exact)
  if (matches.length === 0)
    throw new Error(filter === undefined ? `No ${MANIFEST_FILENAME} found in ${rootDir}` : `No secret matches "${filter}", run ${runCommand('secrets read')} for the list`)
  for (const path of new Set(matches.map(match => match.envPath))) {
    const directory = state.directories.get(dirname(path))!
    const missing = directory.envContent === undefined ? directory.envPath : path === directory.secretsPath && directory.secretsContent === undefined ? path : undefined
    if (missing !== undefined)
      throw new Error(`No ${relative(rootDir, missing)} file found. Run ${runCommand('setup')} first.`)
  }
  if (json) {
    console.log(JSON.stringify(matches.map(({ envPath, key, value, source, related }) => ({
      file: relative(rootDir, envPath),
      key,
      value: value ?? null,
      source,
      ...(related === undefined ? {} : { related: Object.fromEntries(Object.entries(related).map(([name, current]) => [name, current ?? null])) }),
    })), null, 2))
    return
  }
  if (exact !== undefined) {
    for (const match of matches)
      console.log(match.value ?? '')
    return
  }
  const groups = new Map<string, SecretValue[]>()
  for (const match of matches)
    groups.set(match.envPath, [...(groups.get(match.envPath) ?? []), match])
  const blocks = [...groups].map(([path, group]) => {
    const lines = [relative(rootDir, path)]
    const printed = new Set<string>()
    for (const match of group) {
      for (const [name, current] of Object.entries(match.related ?? {})) {
        if (!printed.has(name))
          lines.push(keyValue(name, current ?? ''))
        printed.add(name)
      }
      lines.push(keyValue(match.key, match.value ?? ''))
    }
    return lines.join('\n')
  })
  console.log(blocks.join('\n\n'))
}

/** Why a value cannot be written as a secret, or undefined; never holds the value */
function valueProblem(value: string): string | undefined {
  if (value.length === 0)
    return 'the value must not be empty'
  try {
    formatEnvValue(value)
    return undefined
  } catch (error) {
    return (error as Error).message
  }
}

/**
 * `secrets set KEY [value]`: writes one generate or prompt secret, asked for with a masked prompt when no
 * value is given, then what is derived from it and its links. A link or a derived key is refused with a
 * pointer to the key it follows.
 */
async function set(rootDir: string, key: string | undefined, value: string | undefined): Promise<void> {
  logger.intro('n8n-starter secrets set')

  const state = await readSecretState(rootDir)
  const names = [...new Set(state.declared.filter(isSettable).map(secret => secret.key))].join(', ')
  if (key === undefined) {
    logger.error(`Missing secret key. Expected one of: ${names}`)
    process.exitCode = 1
    return
  }
  const targets = state.declared.filter(secret => secret.key === key && isSettable(secret))
  if (targets.length === 0) {
    const other = state.declared.find(secret => secret.key === key)
    if (other === undefined) {
      logger.error(`Unknown secret "${key}". Expected one of: ${names}`)
    } else if (isLink(other)) {
      const source = linkSource(other, state.declared)
      logger.error(`${key} is a copy of ${source.key} in ${relative(rootDir, secretPath(state, source))}, run ${runCommand(`secrets set ${source.key}`)}`)
    } else {
      const input = derivedInput(other as DeclaredDerived, state.declared)
      logger.error(`${key} is derived from ${input.key} in ${relative(rootDir, secretPath(state, input))}, run ${runCommand(`secrets set ${input.key}`)}`)
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
      validate: (entered) => {
        const problem = valueProblem(entered ?? '')
        return problem === undefined ? undefined : problem[0]!.toUpperCase() + problem.slice(1)
      },
    })
    if (isCancel(entered)) {
      logger.cancel('Secret not changed.')
      return
    }
    resolved = entered
  }
  const problem = valueProblem(resolved)
  if (problem !== undefined) {
    logger.error(`Invalid ${key}: ${problem}`)
    process.exitCode = 1
    return
  }

  for (const target of targets) {
    if (target.entry.source === 'generate' && target.entry.rotation === 'never' && !isSecretUnfilled(state, target))
      logger.warn(`${key} in ${relative(rootDir, secretPath(state, target))} is already set and the data in .volumes/ depends on it`)
  }

  for (const { envPath, key: written, status } of await setSecret(state, key, resolved))
    logger.success(`${written} ${status === 'linked' ? 'linked' : status === 'generated' ? 'derived' : 'set'} in ${relative(rootDir, envPath)}`)
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
