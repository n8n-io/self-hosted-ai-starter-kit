import { readdir } from 'node:fs/promises'
import { join } from 'node:path'

const IGNORED_DIRECTORIES = new Set(['node_modules', 'dist'])

export async function findFiles(rootDir: string, filename: string): Promise<string[]> {
  const matches: string[] = []
  const entries = await readdir(rootDir, { withFileTypes: true })

  for (const entry of entries) {
    const fullPath = join(rootDir, entry.name)
    if (entry.isDirectory()) {
      if (IGNORED_DIRECTORIES.has(entry.name) || entry.name.startsWith('.'))
        continue
      matches.push(...await findFiles(fullPath, filename))
    } else if (entry.isFile() && entry.name === filename) {
      matches.push(fullPath)
    }
  }

  return matches.sort()
}
