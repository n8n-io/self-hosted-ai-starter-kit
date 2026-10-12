import { readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { cancel, intro, isCancel, log, outro, select, text } from '@clack/prompts'
import type { AiRuntime, Config, N8nVariant } from '../schemas/config'
import { AI_RUNTIMES, aiRuntimeSchema, configSchema, domainSchema, N8N_VARIANTS, n8nVariantSchema } from '../schemas/config'
import { parseEnvContent, updateEnvContent } from '../utils/env'

const ENV_FILENAME = '.env'

export async function config(rootDir = process.cwd()) {
  intro('n8n-starter config')

  const envPath = join(rootDir, ENV_FILENAME)
  let content: string
  try {
    content = await readFile(envPath, 'utf-8')
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT')
      throw error
    cancel(`No ${ENV_FILENAME} file found in ${rootDir}. Run \`n8n-starter setup\` first.`)
    process.exitCode = 1
    return
  }

  const current = parseEnvContent(content)

  const domain = await text({
    message: 'The domain to run the Docker Compose services on',
    initialValue: current.DOMAIN ?? 'dev.localhost',
    validate: (value) => domainSchema.safeParse(value).error?.issues[0]?.message,
  })
  if (isCancel(domain)) {
    cancel('Configuration cancelled. No changes were made.')
    return
  }

  const aiRuntime = await select<AiRuntime>({
    message: 'The hardware-supported AI runtime',
    options: AI_RUNTIMES.map(value => ({ value, label: value })),
    initialValue: aiRuntimeSchema.safeParse(current.AI_RUNTIME).data,
  })
  if (isCancel(aiRuntime)) {
    cancel('Configuration cancelled. No changes were made.')
    return
  }

  const n8nVariant = await select<N8nVariant>({
    message: 'Which variant of n8n to run',
    options: N8N_VARIANTS.map(value => ({ value, label: value })),
    initialValue: n8nVariantSchema.safeParse(current.N8N_VARIANT).data,
  })
  if (isCancel(n8nVariant)) {
    cancel('Configuration cancelled. No changes were made.')
    return
  }

  const updates: Config = configSchema.parse({
    DOMAIN: domain,
    AI_RUNTIME: aiRuntime,
    N8N_VARIANT: n8nVariant,
  })

  await writeFile(envPath, updateEnvContent(content, updates))

  for (const [key, value] of Object.entries(updates))
    log.success(`${key}=${value}`)

  outro(`Configuration written to ${ENV_FILENAME}`)
}
