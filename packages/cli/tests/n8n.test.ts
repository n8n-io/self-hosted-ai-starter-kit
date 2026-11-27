import type { DockerRunner } from '../src/utils/docker'
import { existsSync } from 'node:fs'
import { chmod, mkdir, mkdtemp, readdir, readFile, rm, stat, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import * as clack from '@clack/prompts'
import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import { setLogLevel } from '../src/utils/logger'

const { confirmMock, CANCEL } = vi.hoisted(() => ({
  confirmMock: vi.fn(),
  CANCEL: Symbol('clack-cancel'),
}))

vi.mock('@clack/prompts', () => ({
  intro: vi.fn(),
  outro: vi.fn(),
  cancel: vi.fn(),
  confirm: confirmMock,
  isCancel: (value: unknown) => value === CANCEL,
  log: { info: vi.fn(), warn: vi.fn(), success: vi.fn(), error: vi.fn(), step: vi.fn(), message: vi.fn() },
}))

const { exportN8n, importN8n, n8n, readExportCounts } = await import('../src/commands/n8n')

type Files = Record<string, string>

interface FakeN8n {
  running?: boolean
  workflows?: Files
  credentials?: Files
  /** Every docker call with this argument fails */
  failOn?: string
}

/** The compose project `n8n` as the command drives it: `ps`, `exec` in the main container and `cp` both ways */
function fakeDocker({ running = true, workflows = {}, credentials = {}, failOn }: FakeN8n = {}) {
  const calls: string[][] = []
  /** What a `cp` into the container carried, by container path */
  const copiedIn: Record<string, string[]> = {}
  const stored: Record<string, Files> = { workflows, credentials }

  const run: DockerRunner = async (args) => {
    calls.push(args)
    expect(args.slice(0, 3)).toEqual(['compose', '-p', 'n8n'])
    if (failOn !== undefined && args.includes(failOn))
      throw new Error(`Command failed: docker ${args.join(' ')}\nboom`)
    const [action, ...rest] = args.slice(3)
    if (action === 'ps')
      return running ? '0123456789ab\n' : ''
    if (action === 'exec') {
      const [command, subcommand] = rest.slice(4)
      if (command === 'n8n' && subcommand?.startsWith('export:')) {
        const kind = subcommand === 'export:workflow' ? 'workflows' : 'credentials'
        if (Object.keys(stored[kind]!).length === 0)
          throw Object.assign(new Error(`Command failed: docker ${args.join(' ')}`), { stdout: `No ${kind} found with specified filters\n`, stderr: '' })
      }
      return ''
    }
    if (action === 'cp') {
      const [source, target] = rest as [string, string]
      if (source.startsWith('n8n:')) {
        const kind = source.endsWith('/workflows') ? 'workflows' : 'credentials'
        await mkdir(target, { mode: 0o777 })
        await chmod(target, 0o777)
        for (const [name, content] of Object.entries(stored[kind]!))
          await writeFile(join(target, name), content, { mode: 0o666 })
      } else {
        copiedIn[target.replace(/^n8n:/, '')] = await readdir(source)
      }
      return ''
    }
    throw new Error(`Unexpected docker call: ${args.join(' ')}`)
  }

  /** The docker calls without the project prefix, the random container folder replaced by <dir> */
  const commands = () => calls.map(args => args.slice(3).join(' ').replace(/\/tmp\/n8n-starter-[0-9a-f]{12}/g, '<dir>'))
  return { run, calls, commands, copiedIn }
}

let rootDir: string
let previousExitCode: typeof process.exitCode

beforeEach(async () => {
  rootDir = await mkdtemp(join(tmpdir(), 'n8n-starter-n8n-'))
  previousExitCode = process.exitCode
  confirmMock.mockReset()
  vi.mocked(clack.log.error).mockClear()
  vi.mocked(clack.log.warn).mockClear()
  vi.mocked(clack.log.message).mockClear()
  vi.mocked(clack.log.success).mockClear()
  vi.mocked(clack.cancel).mockClear()
})

afterEach(async () => {
  await rm(rootDir, { recursive: true, force: true })
  process.exitCode = previousExitCode
  setLogLevel('info')
})

async function addExport(kind: 'workflows' | 'credentials', files: Files) {
  const dir = join(rootDir, 'export', kind)
  await mkdir(dir, { recursive: true })
  for (const [name, content] of Object.entries(files))
    await writeFile(join(dir, name), content)
}

function mode(path: string) {
  return stat(path).then(stats => stats.mode & 0o777)
}

test('export runs the n8n server CLI in the main container, copies both folders out and removes the container folder', async () => {
  const docker = fakeDocker({ workflows: { 'w1.json': '{"id":"w1"}', 'w2.json': '{"id":"w2"}' }, credentials: { 'c1.json': '{"id":"c1"}' } })

  const counts = await exportN8n(rootDir, docker)

  expect(counts).toEqual({ workflows: 2, credentials: 1 })
  expect(docker.commands()).toEqual([
    'ps --status running -q n8n',
    // readable by node only: it holds the decrypted credentials until it is removed
    'exec -T -u node n8n mkdir -m 700 <dir> <dir>/credentials <dir>/workflows',
    'exec -T -u node n8n n8n export:credentials --all --pretty --separate --decrypted --output=<dir>/credentials',
    // every workflow in its current draft: --published would skip the unpublished ones
    'exec -T -u node n8n n8n export:workflow --all --pretty --separate --output=<dir>/workflows',
    `cp n8n:<dir>/credentials ${join(rootDir, 'export/credentials')}`,
    `cp n8n:<dir>/workflows ${join(rootDir, 'export/workflows')}`,
    'exec -T -u root n8n rm -rf <dir>',
  ])
  expect(await readFile(join(rootDir, 'export/workflows/w1.json'), 'utf-8')).toBe('{"id":"w1"}')
  // one folder per run, the same in every call
  expect(new Set(docker.calls.flat().join(' ').match(/\/tmp\/n8n-starter-[0-9a-f]{12}/g)).size).toBe(1)
})

test('export keeps the files to their owner, whatever mode n8n wrote them with', async () => {
  await exportN8n(rootDir, fakeDocker({ workflows: { 'w1.json': '{}' }, credentials: { 'c1.json': '{}' } }))

  for (const kind of ['credentials', 'workflows']) {
    expect(await mode(join(rootDir, 'export', kind)), kind).toBe(0o700)
    expect(await mode(join(rootDir, 'export', kind, `${kind[0]}1.json`)), kind).toBe(0o600)
  }
})

test('export replaces the previous export, so an item deleted in n8n does not come back with an import', async () => {
  await addExport('workflows', { 'deleted.json': '{}' })
  await addExport('credentials', { 'deleted.json': '{}' })
  await writeFile(join(rootDir, 'export/notes.md'), 'mine')

  await exportN8n(rootDir, fakeDocker({ workflows: { 'w1.json': '{}' }, credentials: { 'c1.json': '{}' } }))

  expect(await readdir(join(rootDir, 'export/workflows'))).toEqual(['w1.json'])
  expect(await readdir(join(rootDir, 'export/credentials'))).toEqual(['c1.json'])
  // only the two folders of the export are replaced
  expect(existsSync(join(rootDir, 'export/notes.md'))).toBe(true)
})

test('an n8n without workflows or credentials exports nothing instead of failing', async () => {
  await addExport('credentials', { 'deleted.json': '{}' })

  const counts = await exportN8n(rootDir, fakeDocker({ workflows: { 'w1.json': '{}' } }))

  expect(counts).toEqual({ workflows: 1, credentials: 0 })
  expect(await readdir(join(rootDir, 'export/credentials'))).toEqual([])
})

test('a failed export keeps the previous export and still removes the container folder', async () => {
  await addExport('workflows', { 'previous.json': '{}' })
  const docker = fakeDocker({ workflows: { 'w1.json': '{}' }, failOn: 'export:workflow' })

  await expect(exportN8n(rootDir, docker)).rejects.toThrow('boom')

  expect(await readdir(join(rootDir, 'export/workflows'))).toEqual(['previous.json'])
  expect(docker.commands().at(-1)).toBe('exec -T -u root n8n rm -rf <dir>')
  expect(docker.commands().some(command => command.startsWith('cp '))).toBe(false)
})

test('export and import stop before touching anything when n8n is not running', async () => {
  await addExport('workflows', { 'w1.json': '{}' })
  const docker = fakeDocker({ running: false })

  await expect(exportN8n(rootDir, docker)).rejects.toThrow('n8n is not running')
  await expect(importN8n(rootDir, docker)).rejects.toThrow('n8n is not running')

  expect(docker.commands()).toEqual(['ps --status running -q n8n', 'ps --status running -q n8n'])
  expect(await readdir(join(rootDir, 'export/workflows'))).toEqual(['w1.json'])
})

test('readExportCounts counts the JSON files per kind, 0 for a missing folder', async () => {
  expect(await readExportCounts(rootDir)).toEqual({ workflows: 0, credentials: 0 })

  await addExport('workflows', { 'w1.json': '{}', 'w2.json': '{}', 'README.md': '' })

  expect(await readExportCounts(rootDir)).toEqual({ workflows: 2, credentials: 0 })
})

test('import copies both folders in, hands them to node and imports the credentials before the workflows', async () => {
  await addExport('workflows', { 'w1.json': '{}', 'w2.json': '{}' })
  await addExport('credentials', { 'c1.json': '{}' })
  const docker = fakeDocker()

  const counts = await importN8n(rootDir, docker)

  expect(counts).toEqual({ workflows: 2, credentials: 1 })
  expect(docker.commands()).toEqual([
    'ps --status running -q n8n',
    'exec -T -u node n8n mkdir -m 700 <dir>',
    `cp ${join(rootDir, 'export/credentials')} n8n:<dir>/credentials`,
    `cp ${join(rootDir, 'export/workflows')} n8n:<dir>/workflows`,
    // docker cp creates the files as root
    'exec -T -u root n8n chown -R node:node <dir>',
    'exec -T -u node n8n n8n import:credentials --separate --input=<dir>/credentials',
    'exec -T -u node n8n n8n import:workflow --separate --input=<dir>/workflows',
    'exec -T -u root n8n rm -rf <dir>',
  ])
  expect(Object.values(docker.copiedIn)).toEqual([['c1.json'], ['w1.json', 'w2.json']])
})

test('import skips a kind without files', async () => {
  await addExport('workflows', { 'w1.json': '{}' })
  await mkdir(join(rootDir, 'export/credentials'))
  const docker = fakeDocker()

  expect(await importN8n(rootDir, docker)).toEqual({ workflows: 1, credentials: 0 })

  expect(docker.commands().filter(command => command.includes('credentials'))).toEqual([])
  expect(docker.commands()).toContain('exec -T -u node n8n n8n import:workflow --separate --input=<dir>/workflows')
})

test('import without an export fails before asking docker', async () => {
  const docker = fakeDocker()

  await expect(importN8n(rootDir, docker)).rejects.toThrow('No workflow or credential file in export/workflows or export/credentials')

  expect(docker.calls).toEqual([])
})

test('a declined import leaves n8n untouched', async () => {
  await addExport('workflows', { 'w1.json': '{}' })
  const docker = fakeDocker()
  const confirm = vi.fn(async () => false)

  expect(await importN8n(rootDir, { ...docker, confirm })).toBeUndefined()

  expect(confirm).toHaveBeenCalledWith({ workflows: 1, credentials: 0 })
  expect(docker.commands()).toEqual(['ps --status running -q n8n'])
})

test('a failed import still removes the container folder with the credentials', async () => {
  await addExport('credentials', { 'c1.json': '{}' })
  const docker = fakeDocker({ failOn: 'import:credentials' })

  await expect(importN8n(rootDir, docker)).rejects.toThrow('boom')

  expect(docker.commands().at(-1)).toBe('exec -T -u root n8n rm -rf <dir>')
})

test('a container folder that cannot be removed is named in a warning without hiding the result', async () => {
  const docker = fakeDocker({ workflows: { 'w1.json': '{}' }, credentials: { 'c1.json': '{}' }, failOn: 'rm' })

  expect(await exportN8n(rootDir, docker)).toEqual({ workflows: 1, credentials: 1 })

  expect(clack.log.warn).toHaveBeenCalledWith(expect.stringMatching(/^Could not remove \/tmp\/n8n-starter-[0-9a-f]{12} inside the n8n container, it may hold credentials in plain text: /))
})

test('n8n export reports the counts and warns about the plain text credentials', async () => {
  await n8n(rootDir, ['export'], {}, fakeDocker({ workflows: { 'w1.json': '{}' }, credentials: { 'c1.json': '{}' } }))

  expect(clack.intro).toHaveBeenCalledWith('n8n-starter n8n export')
  expect(clack.log.success).toHaveBeenCalledWith('Exported 1 workflow(s) to export/workflows')
  expect(clack.log.success).toHaveBeenCalledWith('Exported 1 credential(s) to export/credentials')
  expect(clack.log.warn).toHaveBeenCalledWith(expect.stringContaining('export/credentials holds the credentials in plain text'))
  expect(clack.outro).toHaveBeenCalledWith('Import them with `pnpm run import`')
  expect(process.exitCode).toBe(previousExitCode)
})

test('n8n export without credentials does not warn', async () => {
  await n8n(rootDir, ['export'], {}, fakeDocker({ workflows: { 'w1.json': '{}' } }))

  expect(clack.log.success).toHaveBeenCalledWith('Exported 0 credential(s) to export/credentials')
  expect(clack.log.warn).not.toHaveBeenCalled()
})

test('n8n export names the fix when n8n is not running', async () => {
  await n8n(rootDir, ['export'], {}, fakeDocker({ running: false }))

  expect(clack.log.error).toHaveBeenCalledWith('n8n is not running')
  expect(clack.log.message).toHaveBeenCalledWith('Start the stack with `pnpm run dev` first', { symbol: '💡' })
  expect(process.exitCode).toBe(1)
})

test('n8n import asks with the counts before it imports', async () => {
  await addExport('workflows', { 'w1.json': '{}', 'w2.json': '{}' })
  await addExport('credentials', { 'c1.json': '{}' })
  confirmMock.mockResolvedValue(true)
  const docker = fakeDocker()

  await n8n(rootDir, ['import'], { interactive: true }, docker)

  expect(confirmMock).toHaveBeenCalledWith({ message: 'Import 2 workflow(s) and 1 credential(s) into the running n8n? Items with the same id are overwritten.', initialValue: false })
  expect(docker.commands()).toContain('exec -T -u node n8n n8n import:workflow --separate --input=<dir>/workflows')
  expect(clack.log.success).toHaveBeenCalledWith('Imported 2 workflow(s)')
  expect(clack.log.info).toHaveBeenCalledWith('Imported workflows are unpublished: publish them in n8n')
  expect(clack.outro).toHaveBeenCalledWith('3 item(s) imported.')
  expect(process.exitCode).toBe(previousExitCode)
})

test.each([
  ['declined', false],
  ['cancelled', CANCEL],
])('n8n import %s imports nothing', async (_name, answer) => {
  await addExport('workflows', { 'w1.json': '{}' })
  confirmMock.mockResolvedValue(answer)
  const docker = fakeDocker()

  await n8n(rootDir, ['import'], { interactive: true }, docker)

  expect(docker.commands()).toEqual(['ps --status running -q n8n'])
  expect(clack.cancel).toHaveBeenCalledWith('Import cancelled. Nothing was imported.')
  expect(process.exitCode).toBe(previousExitCode)
})

test('n8n import --yes imports without a prompt', async () => {
  await addExport('workflows', { 'w1.json': '{}' })
  const docker = fakeDocker()

  await n8n(rootDir, ['import'], { yes: true }, docker)

  expect(confirmMock).not.toHaveBeenCalled()
  expect(docker.commands()).toContain('exec -T -u node n8n n8n import:workflow --separate --input=<dir>/workflows')
})

test('n8n import without a terminal and without --yes fails instead of ending on an unanswered prompt', async () => {
  await addExport('workflows', { 'w1.json': '{}' })
  const docker = fakeDocker()

  await n8n(rootDir, ['import'], { interactive: false }, docker)

  expect(confirmMock).not.toHaveBeenCalled()
  expect(docker.commands()).toEqual(['ps --status running -q n8n'])
  expect(clack.log.error).toHaveBeenCalledWith('n8n import asks for a confirmation and there is no terminal to answer it')
  expect(clack.log.message).toHaveBeenCalledWith('Import without it: `pnpm run import --yes`', { symbol: '💡' })
  expect(process.exitCode).toBe(1)
})

test('n8n import names the fix when there is no export', async () => {
  await n8n(rootDir, ['import'], { yes: true }, fakeDocker())

  expect(clack.log.error).toHaveBeenCalledWith('No workflow or credential file in export/workflows or export/credentials')
  expect(clack.log.message).toHaveBeenCalledWith('Create them with `pnpm run export`', { symbol: '💡' })
  expect(process.exitCode).toBe(1)
})

test('a docker failure is reported with exit code 1', async () => {
  await addExport('workflows', { 'w1.json': '{}' })

  await n8n(rootDir, ['import'], { yes: true }, fakeDocker({ failOn: 'chown' }))

  expect(clack.log.error).toHaveBeenCalledWith(expect.stringContaining('boom'))
  expect(process.exitCode).toBe(1)
})

test.each<[string[], string]>([
  [[], 'Missing sub-command for n8n. Expected one of: export, import'],
  [['nope'], 'Unknown sub-command "nope" for n8n. Expected one of: export, import'],
])('n8n %j is rejected without asking docker', async (rest, message) => {
  const docker = fakeDocker()

  await n8n(rootDir, rest, {}, docker)

  expect(clack.log.error).toHaveBeenCalledWith(message)
  expect(process.exitCode).toBe(1)
  expect(docker.calls).toEqual([])
})
