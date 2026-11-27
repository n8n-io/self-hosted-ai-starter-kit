import { z } from 'zod'

/** A provider id of compose/models/models.cloud.json: what n8n reads before the first slash of N8N_INSTANCE_AI_MODEL */
export const ASSISTANT_PROVIDER_ID_PATTERN = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/
/** A model id as its provider names it; an aggregator nests the vendor, as `deepseek/deepseek-v4-pro` on openrouter */
export const ASSISTANT_MODEL_ID_PATTERN = /^[\w.:-]+(\/[\w.:-]+)*$/

/** One model a provider serves */
export const assistantModelSchema = z.object({
  id: z.string().regex(ASSISTANT_MODEL_ID_PATTERN, 'Model ids are the names of the provider, such as claude-opus-5-5 or deepseek/deepseek-v4-pro'),
  label: z.string().min(1, 'label must not be empty'),
  /** A short hint shown after the id by `config N8N_ASSISTANT` */
  note: z.string().min(1, 'note must not be empty').optional(),
}).strict()

/** One cloud provider with the models recommended for the n8n Assistant, the first one offered first */
export const assistantProviderSchema = z.object({
  id: z.string().regex(ASSISTANT_PROVIDER_ID_PATTERN, 'Provider ids are lowercase letters, digits and inner dashes such as anthropic'),
  label: z.string().min(1, 'label must not be empty'),
  models: z.array(assistantModelSchema)
    .min(1, 'a provider needs at least one model')
    .refine(models => new Set(models.map(model => model.id)).size === models.length, 'model ids must be unique within a provider'),
}).strict()

/**
 * The shape of compose/models/models.cloud.json, mirrored for editors by compose/models/models.cloud.schema.json:
 * the cloud models `config N8N_ASSISTANT` offers, nested under their provider. The first model of the first provider is
 * the default of N8N_INSTANCE_AI_MODEL in compose/n8n/docker-compose.yml (see ../../../../SPEC.md)
 */
export const assistantCatalogueSchema = z.object({
  $schema: z.string().optional(),
  providers: z.array(assistantProviderSchema)
    .min(1, 'the catalogue needs at least one provider')
    .refine(providers => new Set(providers.map(provider => provider.id)).size === providers.length, 'provider ids must be unique'),
}).strict()

export type AssistantModel = z.infer<typeof assistantModelSchema>
export type AssistantProvider = z.infer<typeof assistantProviderSchema>
export type AssistantCatalogue = z.infer<typeof assistantCatalogueSchema>
