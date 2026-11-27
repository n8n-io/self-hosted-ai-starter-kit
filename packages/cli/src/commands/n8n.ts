import type { DockerOptions, DockerRunner } from '../utils/docker'
import { randomBytes } from 'node:crypto'
import { chmod, mkdir, readdir, rm } from 'node:fs/promises'
import { join } from 'node:path'
import { confirm, isCancel } from '@clack/prompts'
import { runDocker } from '../utils/docker'
import { runCommand } from '../utils/format'
import { logger } from '../utils/logger'

export const N8N_SUBCOMMANDS = ['export', 'import'] as const

/** The host folder of an export, relative to the repository root and gitignored: one sub-folder per kind */
export const EXPORT_DIRNAME = 'export'

/** What the n8n server CLI moves, in import order: a workflow names its credentials by id, so they come first */
const KINDS = ['credentials', 'workflows'] as const

type Kind = typeof KINDS[number]

export type N8nCounts = Record<Kind, number>

/** The n8n server CLI commands of a kind, see https://docs.n8n.io/deploy/host-n8n/configure-n8n/use-the-command-line */
const SERVER_COMMANDS: Record<Kind, { export: string[], import: string[] }> = {
  // --decrypted: an export that still imports after a reset or into a checkout with another N8N_ENCRYPTION_KEY
  credentials: { export: ['export:credentials', '--all', '--pretty', '--separate', '--decrypted'], import: ['import:credentials', '--separate'] },
  // no --published: with --all it skips every workflow without a published version
  workflows: { export: ['export:workflow', '--all', '--pretty', '--separate'], import: ['import:workflow', '--separate'] },
}

/** The compose project and the main service of every n8n variant file (`name: n8n`, see ../../../../SPEC.md) */
const COMPOSE_PROJECT = 'n8n'
const SERVICE = 'n8n'

/** An error with the line that names its fix */
export class N8nError extends Error {
  constructor(message: string, readonly hint?: string) {
    super(message)
  }
}

function compose(run: DockerRunner, args: string[]): Promise<string> {
  return run(['compose', '-p', COMPOSE_PROJECT, ...args])
}

/** A command in the running main container: the server CLI as `node`, as the n8n docs run it */
function exec(run: DockerRunner, user: 'node' | 'root', command: string[]): Promise<string> {
  return compose(run, ['exec', '-T', '-u', user, SERVICE, ...command])
}

async function assertRunning(run: DockerRunner): Promise<void> {
  const id = await compose(run, ['ps', '--status', 'running', '-q', SERVICE])
  if (id.trim() === '')
    throw new N8nError('n8n is not running', `Start the stack with ${runCommand('dev')} first`)
}

/**
 * A fresh folder inside the container, readable by `node` only: docker cannot mount a host folder into a running
 * container, so the files are copied, and the folder holds the credentials in plain text meanwhile
 */
async function createContainerDir(run: DockerRunner, subfolders: readonly string[] = []): Promise<string> {
  const dir = `/tmp/n8n-starter-${randomBytes(6).toString('hex')}`
  await exec(run, 'node', ['mkdir', '-m', '700', dir, ...subfolders.map(name => `${dir}/${name}`)])
  return dir
}

/** The export is kept to its owner: n8n writes its files for everyone, and they hold credentials and pinned data */
async function restrictToOwner(dir: string): Promise<void> {
  await chmod(dir, 0o700)
  for (const name of await readdir(dir))
    await chmod(join(dir, name), 0o600)
}

/** A leftover folder is named, never silent */
async function removeContainerDir(run: DockerRunner, dir: string): Promise<void> {
  try {
    await exec(run, 'root', ['rm', '-rf', dir])
  } catch (error) {
    logger.warn(`Could not remove ${dir} inside the n8n container, it may hold credentials in plain text: ${(error as Error).message}`)
  }
}

/** n8n exits with code 1 when there is nothing to export: that is an empty export, not a failure */
function isNothingFound(error: unknown): boolean {
  const { message, stdout, stderr } = error as { message?: string, stdout?: string, stderr?: string }
  return /No (?:workflows|credentials) found/.test([message, stdout, stderr].join('\n'))
}

async function countJsonFiles(dir: string): Promise<number> {
  try {
    return (await readdir(dir)).filter(name => name.endsWith('.json')).length
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT')
      throw error
    return 0
  }
}

/** The JSON files of the export folder per kind, 0 for a folder that does not exist */
export async function readExportCounts(rootDir: string): Promise<N8nCounts> {
  return {
    credentials: await countJsonFiles(join(rootDir, EXPORT_DIRNAME, 'credentials')),
    workflows: await countJsonFiles(join(rootDir, EXPORT_DIRNAME, 'workflows')),
  }
}

/**
 * Writes every workflow (its current draft) and every credential (decrypted) of the running n8n to
 * `export/workflows` and `export/credentials`, one JSON file each. Both folders are replaced, so an item
 * deleted in n8n does not come back with the next import; the files are readable by their owner only.
 */
export async function exportN8n(rootDir: string, { run = runDocker }: DockerOptions = {}): Promise<N8nCounts> {
  await assertRunning(run)
  const dir = await createContainerDir(run, KINDS)
  try {
    for (const kind of KINDS) {
      try {
        logger.debug(await exec(run, 'node', ['n8n', ...SERVER_COMMANDS[kind].export, `--output=${dir}/${kind}`]))
      } catch (error) {
        if (!isNothingFound(error))
          throw error
      }
    }
    // the previous export is only replaced once n8n wrote the new one
    await mkdir(join(rootDir, EXPORT_DIRNAME), { recursive: true })
    for (const kind of KINDS) {
      const target = join(rootDir, EXPORT_DIRNAME, kind)
      await rm(target, { recursive: true, force: true })
      await compose(run, ['cp', `${SERVICE}:${dir}/${kind}`, target])
      await restrictToOwner(target)
    }
  } finally {
    await removeContainerDir(run, dir)
  }
  return readExportCounts(rootDir)
}

export interface ImportOptions extends DockerOptions {
  /** Asked once n8n is known to run and before anything is written; `false` leaves n8n untouched */
  confirm?: (counts: N8nCounts) => Promise<boolean>
}

/**
 * Imports `export/credentials`, then `export/workflows` into the running n8n: an item with the same id is
 * overwritten and every workflow arrives unpublished. Resolves with the counts, or with `undefined` when
 * the confirmation was declined.
 */
export async function importN8n(rootDir: string, { run = runDocker, confirm: confirmed = async () => true }: ImportOptions = {}): Promise<N8nCounts | undefined> {
  const counts = await readExportCounts(rootDir)
  if (counts.workflows + counts.credentials === 0)
    throw new N8nError(`No workflow or credential file in ${EXPORT_DIRNAME}/workflows or ${EXPORT_DIRNAME}/credentials`, `Create them with ${runCommand('export')}`)
  await assertRunning(run)
  if (!await confirmed(counts))
    return undefined

  const kinds = KINDS.filter(kind => counts[kind] > 0)
  const dir = await createContainerDir(run)
  try {
    for (const kind of kinds)
      await compose(run, ['cp', join(rootDir, EXPORT_DIRNAME, kind), `${SERVICE}:${dir}/${kind}`])
    // docker cp creates the files as root with the modes of the host, which keep them to their owner
    await exec(run, 'root', ['chown', '-R', 'node:node', dir])
    for (const kind of kinds)
      logger.debug(await exec(run, 'node', ['n8n', ...SERVER_COMMANDS[kind].import, `--input=${dir}/${kind}`]))
  } finally {
    await removeContainerDir(run, dir)
  }
  return counts
}

async function runExport(rootDir: string, docker: DockerOptions): Promise<void> {
  const counts = await exportN8n(rootDir, docker)
  logger.success(`Exported ${counts.workflows} workflow(s) to ${EXPORT_DIRNAME}/workflows`)
  logger.success(`Exported ${counts.credentials} credential(s) to ${EXPORT_DIRNAME}/credentials`)
  if (counts.credentials > 0)
    logger.warn(`${EXPORT_DIRNAME}/credentials holds the credentials in plain text: the folder is gitignored, delete it when it is no longer needed`)
  logger.outro(`Import them with ${runCommand('import')}`)
}

async function runImport(rootDir: string, yes: boolean, interactive: boolean, docker: DockerOptions): Promise<void> {
  const counts = await importN8n(rootDir, {
    ...docker,
    confirm: async ({ workflows, credentials }) => {
      if (yes)
        return true
      // without a terminal the prompt ends the process with exit code 0 and nothing imported
      if (!interactive)
        throw new N8nError('n8n import asks for a confirmation and there is no terminal to answer it', `Import without it: ${runCommand('import --yes')}`)
      const confirmed = await confirm({
        message: `Import ${workflows} workflow(s) and ${credentials} credential(s) into the running n8n? Items with the same id are overwritten.`,
        initialValue: false,
      })
      return !isCancel(confirmed) && confirmed
    },
  })
  if (counts === undefined) {
    logger.cancel('Import cancelled. Nothing was imported.')
    return
  }
  logger.success(`Imported ${counts.credentials} credential(s)`)
  logger.success(`Imported ${counts.workflows} workflow(s)`)
  if (counts.workflows > 0) {
    logger.info('Imported workflows are unpublished: publish them in n8n')
    logger.info('A workflow that was published before the import keeps its schedule triggers until n8n restarts, unless n8n runs in queue mode')
  }
  logger.outro(`${counts.workflows + counts.credentials} item(s) imported.`)
}

/** `n8n <export|import> [--yes]`, see ../../README.md; `interactive` is whether a terminal can answer the confirmation */
export async function n8n(rootDir = process.cwd(), [subcommand]: string[] = [], { yes = false, interactive = process.stdin.isTTY === true }: { yes?: boolean, interactive?: boolean } = {}, docker: DockerOptions = {}) {
  if (subcommand !== 'export' && subcommand !== 'import') {
    logger.error(`${subcommand === undefined ? 'Missing' : `Unknown`} sub-command${subcommand === undefined ? '' : ` "${subcommand}"`} for n8n. Expected one of: ${N8N_SUBCOMMANDS.join(', ')}`)
    process.exitCode = 1
    return
  }
  logger.intro(`n8n-starter n8n ${subcommand}`)
  try {
    if (subcommand === 'export')
      await runExport(rootDir, docker)
    else
      await runImport(rootDir, yes, interactive, docker)
  } catch (error) {
    // a docker failure carries the command and what it wrote to stderr
    logger.error((error as Error).message)
    if (error instanceof N8nError && error.hint !== undefined)
      logger.hint(error.hint)
    process.exitCode = 1
  }
}
