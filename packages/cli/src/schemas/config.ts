import { z } from 'zod'

// The first entry of each list is the default of the root .env.template and is offered first by `config`
export const AI_RUNTIMES = ['cpu-arm64', 'cpu-x86-64', 'gpu-nvidia', 'gpu-amd'] as const
export const AI_ENGINES = ['ollama', 'vllm'] as const
export const N8N_VARIANTS = ['dev', 'build', 'community', 'enterprise'] as const
// The gateways in front of the model servers; none runs by default, so the template leaves AI_GATEWAY empty
export const AI_GATEWAYS = ['litellm'] as const

export const domainSchema = z
  .string()
  .min(1, 'Domain must not be empty')
  .regex(/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/i, 'Domain must be a valid hostname (e.g. n8n.localhost)')

export const aiRuntimeSchema = z.enum(AI_RUNTIMES)
export const aiEngineSchema = z.enum(AI_ENGINES)
/** Empty runs no gateway: the default of the template, and of a root .env written before the key existed */
export const aiGatewaySchema = z.enum(['', ...AI_GATEWAYS], `Gateway must be empty for none, or one of: ${AI_GATEWAYS.join(', ')}`)
/**
 * Comma separated model ids of compose/models/models.json that Tilt starts with the stack, or empty to start none;
 * each id matches MODEL_ID_PATTERN of ./models.ts
 */
export const aiModelsSchema = z
  .string()
  .regex(/^([a-z0-9]([a-z0-9-]*[a-z0-9])?(,[a-z0-9]([a-z0-9-]*[a-z0-9])?)*)?$/, 'Models must be comma separated lowercase ids such as qwen3-5-0-8b,qwen3-5-4b, or empty')
export const n8nVariantSchema = z.enum(N8N_VARIANTS)

export const configSchema = z.object({
  DOMAIN: domainSchema,
  AI_RUNTIME: aiRuntimeSchema,
  AI_ENGINE: aiEngineSchema,
  AI_GATEWAY: aiGatewaySchema.default(''),
  AI_MODELS: aiModelsSchema,
  N8N_VARIANT: n8nVariantSchema,
})

export type AiRuntime = z.infer<typeof aiRuntimeSchema>
export type AiEngine = z.infer<typeof aiEngineSchema>
export type AiGateway = typeof AI_GATEWAYS[number]
export type N8nVariant = z.infer<typeof n8nVariantSchema>
export type Config = z.infer<typeof configSchema>
