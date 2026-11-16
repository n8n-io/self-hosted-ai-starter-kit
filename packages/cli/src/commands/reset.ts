import { rm } from 'node:fs/promises'
import { relative } from 'node:path'
import { confirm, isCancel } from '@clack/prompts'
import { findFiles } from '../utils/files'
import { runCommand } from '../utils/format'
import { logger } from '../utils/logger'
import { isSecretUnfilled, readSecretState, secretPath, SECRETS_FILENAME } from './secrets'

const ENV_FILENAME = '.env'

/** Every file `setup` generated: the .env files and the .env.secrets beside them, also one left without its .env */
export async function findEnvFiles(rootDir: string): Promise<string[]> {
  return [...await findFiles(rootDir, ENV_FILENAME), ...await findFiles(rootDir, SECRETS_FILENAME)].sort()
}

/** The generated secrets the data in .volumes/ depends on (rotation manual or never, see ./secrets.ts), as `KEY (path)` */
async function boundSecrets(rootDir: string): Promise<string[]> {
  const state = await readSecretState(rootDir)
  return state.declared
    .filter(secret => secret.entry.source === 'generate' && secret.entry.rotation !== 'free' && !isSecretUnfilled(state, secret))
    .map(secret => `${secret.key} (${relative(rootDir, secretPath(state, secret))})`)
}

export async function reset(rootDir = process.cwd()) {
  logger.intro('n8n-starter reset')

  const envFiles = await findEnvFiles(rootDir)

  if (envFiles.length === 0) {
    logger.outro('No generated files found. Nothing to delete.')
    return
  }

  logger.warn('The following generated file(s) will be deleted:')
  for (const file of envFiles)
    logger.info(relative(rootDir, file))

  // a manifest problem is reported by setup and verify, it must not block a reset
  try {
    const bound = await boundSecrets(rootDir)
    if (bound.length > 0)
      logger.warn(`The data in .volumes/ needs ${bound.join(', ')}: back them up with ${runCommand('secrets read')} first`)
  } catch {}

  const confirmed = await confirm({
    message: `Delete ${envFiles.length} generated file(s)?`,
    initialValue: false,
  })

  if (isCancel(confirmed) || !confirmed) {
    logger.cancel('Reset cancelled. No files were deleted.')
    return
  }

  for (const file of envFiles) {
    await rm(file)
    logger.success(`Deleted ${relative(rootDir, file)}`)
  }

  logger.outro(`${envFiles.length} file(s) deleted.`)
}
