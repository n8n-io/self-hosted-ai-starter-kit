import type { DockerNetworkResult } from '../utils/docker'
import type { PlatformOptions } from '../utils/platform'
import type { SecretWriteResult } from './secrets'
import { constants } from 'node:fs'
import { copyFile, readFile, writeFile } from 'node:fs/promises'
import { dirname, join, relative } from 'node:path'
import { aiRuntimeSchema } from '../schemas/config'
import { ensureDockerNetworks } from '../utils/docker'
import { parseEnvContent, updateEnvContent } from '../utils/env'
import { findFiles } from '../utils/files'
import { logger } from '../utils/logger'
import { detectPlatform, formatPlatform, runtimeMismatch } from '../utils/platform'
import { checkSecrets, fillSecrets, formatSecretCheck, readRootConfigIfValid, readSecretState } from './secrets'

const TEMPLATE_FILENAME = '.env.template'
const ENV_FILENAME = '.env'

/**
 * The compose specs declare these as external networks, so they must exist
 * before `tilt up`. n8n-starter-public holds traefik and every container it routes to
 * (label traefik.enable=true); n8n-starter-private holds everything else, such as
 * databases and storage.
 */
export const DOCKER_NETWORKS = ['n8n-starter-public', 'n8n-starter-private']

export interface EnvFileResult {
  templatePath: string
  envPath: string
  status: 'created' | 'skipped'
}

export async function findEnvTemplates(rootDir: string): Promise<string[]> {
  return findFiles(rootDir, TEMPLATE_FILENAME)
}

export async function generateEnvFiles(rootDir: string): Promise<EnvFileResult[]> {
  const templates = await findEnvTemplates(rootDir)
  const results: EnvFileResult[] = []

  for (const templatePath of templates) {
    const envPath = join(dirname(templatePath), ENV_FILENAME)
    try {
      // COPYFILE_EXCL never overwrites an existing .env, which may hold user edits
      await copyFile(templatePath, envPath, constants.COPYFILE_EXCL)
      results.push({ templatePath, envPath, status: 'created' })
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'EEXIST')
        throw error
      results.push({ templatePath, envPath, status: 'skipped' })
    }
  }

  return results
}

/**
 * AI_RUNTIME of the root .env against the detected platform (see ../utils/platform.ts): a root .env created in
 * this run gets the detected runtime instead of the template default, the one value setup sets in a file it
 * created itself; an existing root .env is never touched, a mismatch there is a warning. Returns the written
 * runtime, if any.
 */
export async function applyDetectedRuntime(root: EnvFileResult, docker: PlatformOptions = {}): Promise<string | undefined> {
  const platform = await detectPlatform(docker)
  logger.info(`Detected ${formatPlatform(platform)}`)
  if (platform.runtime === undefined)
    return undefined
  const content = await readFile(root.envPath, 'utf-8')
  const current = parseEnvContent(content).AI_RUNTIME
  if (current === undefined)
    return undefined
  if (root.status === 'created') {
    if (current === platform.runtime)
      return undefined
    await writeFile(root.envPath, updateEnvContent(content, { AI_RUNTIME: platform.runtime }))
    logger.success(`AI_RUNTIME=${platform.runtime} (detected)`)
    return platform.runtime
  }
  const parsed = aiRuntimeSchema.safeParse(current)
  const mismatch = parsed.success ? runtimeMismatch(platform, parsed.data) : undefined
  if (mismatch !== undefined)
    logger.warn(mismatch)
  return undefined
}

export async function setup(rootDir = process.cwd(), docker: PlatformOptions = {}) {
  logger.intro('n8n-starter setup')

  const results = await generateEnvFiles(rootDir)

  if (results.length === 0) {
    logger.warn(`No ${TEMPLATE_FILENAME} files found in ${rootDir}`)
  }

  for (const { envPath, status } of results) {
    const path = relative(rootDir, envPath)
    if (status === 'created')
      logger.success(`Created ${path}`)
    else
      logger.info(`Skipped ${path} (already exists)`)
  }

  // before the secrets, whose `required` conditions read the root .env
  const root = results.find(result => result.envPath === join(rootDir, ENV_FILENAME))
  if (root !== undefined)
    await applyDetectedRuntime(root, docker)

  // the secrets of the .env files just created or still unfilled, see ../../../../SPEC.md; a human secret
  // the current root .env requires (the enterprise license) is pointed at, never prompted for here
  let secrets: SecretWriteResult[] = []
  try {
    secrets = await fillSecrets(rootDir)
    for (const { envPath, key, status } of secrets)
      logger.success(`${status === 'generated' ? 'Generated' : 'Linked'} ${key} in ${relative(rootDir, envPath)}`)
    const config = await readRootConfigIfValid(rootDir)
    for (const check of checkSecrets(await readSecretState(rootDir), config)) {
      if (check.status === 'required')
        logger.warn(formatSecretCheck(rootDir, check))
    }
  } catch (error) {
    logger.error((error as Error).message)
    process.exitCode = 1
  }

  let networks: DockerNetworkResult[] = []
  try {
    networks = await ensureDockerNetworks(DOCKER_NETWORKS, docker)
  } catch (error) {
    logger.error(`Could not create the docker networks ${DOCKER_NETWORKS.join(', ')}. Is Docker installed and running?`)
    logger.error((error as Error).message)
    process.exitCode = 1
  }

  for (const { name, status } of networks) {
    if (status === 'created')
      logger.success(`Created docker network ${name}`)
    else
      logger.info(`Skipped docker network ${name} (already exists)`)
  }

  const created = results.filter(r => r.status === 'created').length
  const skipped = results.length - created
  const generated = secrets.filter(s => s.status === 'generated').length
  const linked = secrets.length - generated
  const networksCreated = networks.filter(n => n.status === 'created').length
  logger.outro(`${created} file(s) created, ${skipped} skipped. ${generated} secret(s) generated, ${linked} linked. ${networksCreated} docker network(s) created.`)
}
