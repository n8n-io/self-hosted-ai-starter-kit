import type { DockerOptions } from '../utils/docker'
import type { Platform, PlatformOptions } from '../utils/platform'
import type { RequirementCheck, RequirementOptions } from '../utils/requirements'
import type { SecretCheck } from './secrets'
import { access } from 'node:fs/promises'
import { dirname, join, relative } from 'node:path'
import { listDockerNetworks } from '../utils/docker'
import { runCommand } from '../utils/format'
import { logger } from '../utils/logger'
import { detectPlatform, formatPlatform, runtimeMismatch } from '../utils/platform'
import { checkRequirements } from '../utils/requirements'
import { checkSecrets, FAILED_SECRET_STATUSES, formatSecretCheck, readRootConfigIfValid, readSecretState } from './secrets'
import { DOCKER_NETWORKS, findEnvTemplates } from './setup'

const ENV_FILENAME = '.env'

export interface EnvFileCheck {
  templatePath: string
  envPath: string
  exists: boolean
}

export interface DockerNetworkCheck {
  name: string
  exists: boolean
}

export interface VerifyResult {
  /** The node, docker and docker compose versions against REQUIREMENTS (see ../utils/requirements.ts) */
  requirements: RequirementCheck[]
  envFiles: EnvFileCheck[]
  /** Every declared secret of a .env that exists (see ./secrets.ts); empty when a manifest is invalid */
  secrets: SecretCheck[]
  /** Set when a .env.secrets.json is missing its template, invalid or links to nothing. */
  secretsError?: string
  networks: DockerNetworkCheck[]
  /** Set when the docker CLI could not be queried at all. */
  dockerError?: string
  /** The detected platform (see ../utils/platform.ts); absent when docker could not be queried */
  platform?: Platform
  /** Set when AI_RUNTIME of the root .env is not the runtime the platform suggests; a warning, never a failure */
  runtimeWarning?: string
  ok: boolean
}

/** The probes verify runs: the tool versions, the docker networks and the platform */
export type VerifyProbeOptions = RequirementOptions & PlatformOptions

async function fileExists(path: string): Promise<boolean> {
  try {
    await access(path)
    return true
  } catch {
    return false
  }
}

export async function verifyEnvFiles(rootDir: string): Promise<EnvFileCheck[]> {
  const templates = await findEnvTemplates(rootDir)
  const checks: EnvFileCheck[] = []

  for (const templatePath of templates) {
    const envPath = join(dirname(templatePath), ENV_FILENAME)
    checks.push({ templatePath, envPath, exists: await fileExists(envPath) })
  }

  return checks
}

export async function verifyDockerNetworks(names: string[], options: DockerOptions = {}): Promise<DockerNetworkCheck[]> {
  const existing = await listDockerNetworks(options)
  return names.map(name => ({ name, exists: existing.includes(name) }))
}

export async function verifyEnvironment(rootDir: string, docker: VerifyProbeOptions = {}): Promise<VerifyResult> {
  // a tool that cannot be queried fails its own check; only the network listing below reports a docker error
  const requirements = await checkRequirements(docker)
  const envFiles = await verifyEnvFiles(rootDir)

  // the prompt conditions and the runtime check need the root .env; without a valid one only the generated
  // and linked secrets are checked
  const config = await readRootConfigIfValid(rootDir)
  let secrets: SecretCheck[] = []
  let secretsError: string | undefined
  try {
    secrets = checkSecrets(await readSecretState(rootDir), config)
  } catch (error) {
    secretsError = (error as Error).message
  }

  let networks: DockerNetworkCheck[] = []
  let dockerError: string | undefined
  try {
    networks = await verifyDockerNetworks(DOCKER_NETWORKS, docker)
  } catch (error) {
    dockerError = (error as Error).message
  }

  // the platform is informational and an AI_RUNTIME that does not fit it a warning (see ../utils/platform.ts)
  let platform: Platform | undefined
  let runtimeWarning: string | undefined
  if (dockerError === undefined) {
    platform = await detectPlatform(docker)
    if (config !== undefined)
      runtimeWarning = runtimeMismatch(platform, config.AI_RUNTIME)
  }

  const ok = requirements.every(check => check.ok)
    && dockerError === undefined
    && secretsError === undefined
    && envFiles.every(check => check.exists)
    && secrets.every(check => !FAILED_SECRET_STATUSES.includes(check.status))
    && networks.every(check => check.exists)

  return { requirements, envFiles, secrets, secretsError, networks, dockerError, platform, runtimeWarning, ok }
}

/** The lines of a verify run by level, plus the commands that fix the failures; the text and the --json output print the same report */
export interface VerifyReport {
  ok: boolean
  success: string[]
  info: string[]
  warnings: string[]
  errors: string[]
  hints: string[]
}

export interface VerifyOptions {
  /** Print the report as one JSON document on stdout and nothing else (the Tiltfile gate reads it) */
  json?: boolean
}

export function formatVerifyResult(rootDir: string, result: VerifyResult): VerifyReport {
  const report: VerifyReport = { ok: result.ok, success: [], info: [], warnings: [], errors: [], hints: [] }

  // the tool versions come first: everything below runs on them
  for (const { name, minimum, installed, ok, error } of result.requirements) {
    if (ok)
      report.success.push(`Found ${name} ${installed} (${minimum} or newer required)`)
    else if (installed !== undefined)
      report.errors.push(`${name} ${installed} is older than the required ${minimum}`)
    else
      report.errors.push(`${name} not found: ${error} (${minimum} or newer required)`)
  }

  if (result.envFiles.length === 0)
    report.warnings.push(`No .env.template files found in ${rootDir}`)

  for (const { envPath, exists } of result.envFiles) {
    const path = relative(rootDir, envPath)
    if (exists)
      report.success.push(`Found ${path}`)
    else
      report.errors.push(`Missing ${path}`)
  }

  if (result.secretsError !== undefined)
    report.errors.push(result.secretsError)

  for (const check of result.secrets) {
    const line = formatSecretCheck(rootDir, check)
    if (FAILED_SECRET_STATUSES.includes(check.status))
      report.errors.push(line)
    else if (check.status === 'unset')
      report.info.push(line)
    else
      report.success.push(line)
  }

  if (result.dockerError !== undefined) {
    report.errors.push('Could not list the docker networks. Is Docker installed and running?')
    report.errors.push(result.dockerError)
  }

  for (const { name, exists } of result.networks) {
    if (exists)
      report.success.push(`Found docker network ${name}`)
    else
      report.errors.push(`Missing docker network ${name}`)
  }

  if (result.platform !== undefined)
    report.info.push(`Detected ${formatPlatform(result.platform)}`)
  // the warning names its own fix (`pnpm run config AI_RUNTIME <runtime>`), so no hint follows it
  if (result.runtimeWarning !== undefined)
    report.warnings.push(result.runtimeWarning)

  // `setup` creates the missing files and networks and fills the generated and linked secrets; a required
  // human secret names `secrets set` on its own line, an invalid manifest names its file, docker must be started
  const setupFixes = result.envFiles.some(check => !check.exists)
    || result.secrets.some(check => check.status === 'missing' || check.status === 'mismatch')
    || result.networks.some(check => !check.exists)
  if (setupFixes)
    report.hints.push(`Run ${runCommand('setup')} to create the missing files, secrets and networks.`)
  // no root script installs a tool, so the hint names the documentation of the requirements
  if (result.requirements.some(check => !check.ok))
    report.hints.push('Install the versions listed under Prerequisites in README.md.')

  return report
}

export async function verify(rootDir = process.cwd(), docker: VerifyProbeOptions = {}, { json = false }: VerifyOptions = {}): Promise<boolean> {
  if (!json)
    logger.intro('n8n-starter verify')

  const report = formatVerifyResult(rootDir, await verifyEnvironment(rootDir, docker))

  if (!report.ok)
    process.exitCode = 1

  if (json) {
    console.log(JSON.stringify(report, null, 2))
    return report.ok
  }

  for (const line of report.warnings)
    logger.warn(line)
  for (const line of report.success)
    logger.success(line)
  for (const line of report.info)
    logger.info(line)
  for (const line of report.errors)
    logger.error(line)
  for (const line of report.hints)
    logger.hint(line)

  logger.outro(report.ok ? 'Environment verified.' : 'Environment incomplete.')

  return report.ok
}
