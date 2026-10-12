import { z } from 'zod'

export const AI_RUNTIMES = ['cpu-x86-64', 'cpu-arm64', 'apple-silicon', 'dgx-spark', 'gpu-nvidia', 'gpu-amd'] as const
export const N8N_VARIANTS = ['base', 'community', 'enterprise'] as const

export const domainSchema = z
  .string()
  .min(1, 'Domain must not be empty')
  .regex(/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/i, 'Domain must be a valid hostname (e.g. dev.localhost)')

export const aiRuntimeSchema = z.enum(AI_RUNTIMES)
export const n8nVariantSchema = z.enum(N8N_VARIANTS)

export const configSchema = z.object({
  DOMAIN: domainSchema,
  AI_RUNTIME: aiRuntimeSchema,
  N8N_VARIANT: n8nVariantSchema,
})

export type AiRuntime = z.infer<typeof aiRuntimeSchema>
export type N8nVariant = z.infer<typeof n8nVariantSchema>
export type Config = z.infer<typeof configSchema>
