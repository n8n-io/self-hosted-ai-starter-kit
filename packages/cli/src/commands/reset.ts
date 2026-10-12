import { rm } from 'node:fs/promises'
import { relative } from 'node:path'
import { cancel, confirm, intro, isCancel, log, outro } from '@clack/prompts'
import { findFiles } from '../utils/files'

const ENV_FILENAME = '.env'

export async function findEnvFiles(rootDir: string): Promise<string[]> {
  return findFiles(rootDir, ENV_FILENAME)
}

export async function reset(rootDir = process.cwd()) {
  intro('n8n-starter reset')

  const envFiles = await findEnvFiles(rootDir)

  if (envFiles.length === 0) {
    outro(`No ${ENV_FILENAME} files found. Nothing to delete.`)
    return
  }

  log.warn(`The following ${ENV_FILENAME} file(s) will be deleted:`)
  for (const file of envFiles)
    log.info(relative(rootDir, file))

  const confirmed = await confirm({
    message: `Delete ${envFiles.length} ${ENV_FILENAME} file(s)?`,
    initialValue: false,
  })

  if (isCancel(confirmed) || !confirmed) {
    cancel('Reset cancelled. No files were deleted.')
    return
  }

  for (const file of envFiles) {
    await rm(file)
    log.success(`Deleted ${relative(rootDir, file)}`)
  }

  outro(`${envFiles.length} file(s) deleted.`)
}
