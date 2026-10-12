import { constants } from 'node:fs'
import { copyFile } from 'node:fs/promises'
import { dirname, join, relative } from 'node:path'
import { intro, log, outro } from '@clack/prompts'
import { findFiles } from '../utils/files'

const TEMPLATE_FILENAME = '.env.template'
const ENV_FILENAME = '.env'

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

export async function setup(rootDir = process.cwd()) {
  intro('n8n-starter setup')

  const results = await generateEnvFiles(rootDir)

  if (results.length === 0) {
    log.warn(`No ${TEMPLATE_FILENAME} files found in ${rootDir}`)
  }

  for (const { envPath, status } of results) {
    const path = relative(rootDir, envPath)
    if (status === 'created')
      log.success(`Created ${path}`)
    else
      log.info(`Skipped ${path} (already exists)`)
  }

  const created = results.filter(r => r.status === 'created').length
  const skipped = results.length - created
  outro(`${created} file(s) created, ${skipped} skipped.`)
}
