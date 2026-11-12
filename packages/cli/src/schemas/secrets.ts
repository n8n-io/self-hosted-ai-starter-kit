import { z } from 'zod'
import { aiEngineSchema, aiRuntimeSchema, n8nVariantSchema } from './config'

/** A key of a .env.secrets.json manifest: an env name, the shape updateEnvContent matches (see ../utils/env.ts) */
export const SECRET_KEY_PATTERN = /^[A-Z][A-Z0-9_]*$/
export const secretKeySchema = z.string().regex(SECRET_KEY_PATTERN, 'Secret keys are upper case env names such as N8N_ENCRYPTION_KEY')

// The first entry of each list is the default of a manifest entry that omits the field
export const SECRET_SOURCES = ['generate', 'prompt', 'link'] as const
export const SECRET_ROTATIONS = ['free', 'manual', 'never'] as const
export const SECRET_ENCODINGS = ['hex', 'base64url'] as const
export const SECRET_PREFIX_PATTERN = /^[A-Za-z0-9_-]*$/

const descriptionSchema = z.string().min(1, 'description must not be empty')

/** The root .env values under which a prompt secret must be set; every listed key must match */
export const secretRequiredSchema = z.object({
  N8N_VARIANT: z.array(n8nVariantSchema).min(1).optional(),
  AI_ENGINE: z.array(aiEngineSchema).min(1).optional(),
  AI_RUNTIME: z.array(aiRuntimeSchema).min(1).optional(),
}).strict().refine(required => Object.keys(required).length > 0, 'required must name at least one root .env key')

/** A random value `setup` writes once; rotation says what changing it later costs (see ../../../../SPEC.md) */
export const generateSecretSchema = z.object({
  source: z.literal('generate'),
  description: descriptionSchema,
  rotation: z.enum(SECRET_ROTATIONS).default('free'),
  bytes: z.int().min(16).max(64).default(32),
  encoding: z.enum(SECRET_ENCODINGS).default('hex'),
  prefix: z.string().regex(SECRET_PREFIX_PATTERN, 'prefix may only hold letters, digits, dashes and underscores').default(''),
}).strict()

/** A value a human sets with `secrets set`; required only under the listed root .env values, optional without them */
export const promptSecretSchema = z.object({
  source: z.literal('prompt'),
  description: descriptionSchema,
  required: secretRequiredSchema.optional(),
}).strict()

/** A copy of a generate or prompt secret of another directory, `from` relative to this manifest */
export const linkSecretSchema = z.object({
  source: z.literal('link'),
  from: z.string().min(1, 'from must not be empty').refine(from => !from.startsWith('/'), 'from is a directory relative to the manifest'),
  key: secretKeySchema,
}).strict()

export const secretEntrySchema = z.discriminatedUnion('source', [generateSecretSchema, promptSecretSchema, linkSecretSchema])

/** The shape of a .env.secrets.json next to a .env.template, mirrored for editors by compose/.env.secrets.schema.json */
export const secretsManifestSchema = z.object({
  $schema: z.string().optional(),
  secrets: z.record(secretKeySchema, secretEntrySchema).refine(secrets => Object.keys(secrets).length > 0, 'secrets must not be empty'),
}).strict()

export type GenerateSecret = z.infer<typeof generateSecretSchema>
export type PromptSecret = z.infer<typeof promptSecretSchema>
export type LinkSecret = z.infer<typeof linkSecretSchema>
export type SecretEntry = z.infer<typeof secretEntrySchema>
export type SecretRequired = z.infer<typeof secretRequiredSchema>
export type SecretsManifest = z.infer<typeof secretsManifestSchema>
