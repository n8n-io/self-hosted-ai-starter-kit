import { z } from 'zod'
import { AI_RUNTIMES } from './config'

/**
 * A model id of compose/models/models.json: the AI_MODELS value and a plain DNS label, since the docker names of
 * the model are `<engine>-<id>` (see ../../../../SPEC.md); one entry per model, served by every engine that has a block
 */
export const MODEL_ID_PATTERN = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/
/** A DNS label holds 63 characters, minus the longest engine prefix `vllm-` */
export const MODEL_ID_MAX_LENGTH = 58
export const modelIdSchema = z
  .string()
  .regex(MODEL_ID_PATTERN, 'Model ids are DNS labels: lowercase letters, digits and inner dashes such as qwen3-5-0-8b')
  .max(MODEL_ID_MAX_LENGTH, `Model ids hold at most ${MODEL_ID_MAX_LENGTH} characters`)

// how one engine serves the model: its name there, what it needs and where it runs; vllm adds its serve arguments
const servingSchema = z.object({
  model: z.string().min(1, 'model must not be empty'),
  /** The approximate memory in GB for weights and context, rendered with `~` and the unit by `models select` */
  memory: z.number().positive().optional(),
  /** A short hint shown after the memory, e.g. what the model needs on a runtime */
  note: z.string().min(1, 'note must not be empty').optional(),
  /** The AI_RUNTIME values the model runs on, every runtime when omitted */
  runtimes: z.array(z.enum(AI_RUNTIMES)).min(1).optional(),
})

export const ollamaServingSchema = servingSchema.strict()
export const vllmServingSchema = servingSchema.extend({ args: z.string() }).strict()

/** One model: its id and label, and a block per engine that serves it */
export const modelSchema = z.object({
  id: modelIdSchema,
  label: z.string().min(1, 'label must not be empty'),
  ollama: ollamaServingSchema.optional(),
  vllm: vllmServingSchema.optional(),
}).strict().refine(model => model.ollama !== undefined || model.vllm !== undefined, 'a model needs an ollama or a vllm block')

/** The shape of compose/models/models.json, mirrored for editors by compose/models/models.schema.json */
export const modelsCatalogueSchema = z.object({
  $schema: z.string().optional(),
  models: z.array(modelSchema)
    .refine(models => new Set(models.map(model => model.id)).size === models.length, 'model ids must be unique'),
}).strict()

export type Model = z.infer<typeof modelSchema>
export type ModelsCatalogue = z.infer<typeof modelsCatalogueSchema>

/** A model as one engine serves it: the id and label of the model with the fields of the engine's block */
export type OllamaModel = Pick<Model, 'id' | 'label'> & z.infer<typeof ollamaServingSchema>
export type VllmModel = Pick<Model, 'id' | 'label'> & z.infer<typeof vllmServingSchema>
export type ModelEntry = OllamaModel | VllmModel
