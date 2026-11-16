import { z } from 'zod'
import { aiEngineSchema, aiRuntimeSchema, n8nVariantSchema } from './config'

/** A key of a .env.json manifest: an env name, the shape updateEnvContent matches (see ../utils/env.ts) */
export const SECRET_KEY_PATTERN = /^[A-Z][A-Z0-9_]*$/
export const secretKeySchema = z.string().regex(SECRET_KEY_PATTERN, 'Secret keys are upper case env names such as N8N_ENCRYPTION_KEY')

// The first entry of each list is the default of a manifest entry that omits the field
export const SECRET_SOURCES = ['generate', 'prompt', 'link'] as const
export const SECRET_ROTATIONS = ['free', 'manual', 'never'] as const
export const SECRET_ENCODINGS = ['hex', 'base64url'] as const
export const SECRET_PREFIX_PATTERN = /^[A-Za-z0-9_-]*$/
/** The file beside the manifest that holds a generated value: .env is what compose reads, .env.secrets what no container reads */
export const SECRET_FILES = ['.env', '.env.secrets'] as const
export const GENERATOR_TYPES = ['random', 'bcrypt'] as const
/** The cost of a bcrypt generator; n8n hashes with 10 */
export const BCRYPT_ROUNDS = { min: 4, max: 15, default: 10 } as const

const descriptionSchema = z.string().min(1, 'description must not be empty')

/** The keys of the same template that are no secrets but belong to one, such as the email of a login; `secrets read` prints them with it */
const relatedSchema = z.array(secretKeySchema).min(1, 'related must name at least one key')

/** The root .env values under which a prompt secret must be set; every listed key must match */
export const secretRequiredSchema = z.object({
  N8N_VARIANT: z.array(n8nVariantSchema).min(1).optional(),
  AI_ENGINE: z.array(aiEngineSchema).min(1).optional(),
  AI_RUNTIME: z.array(aiRuntimeSchema).min(1).optional(),
}).strict().refine(required => Object.keys(required).length > 0, 'required must name at least one root .env key')

/** Random bytes, the generator of an entry that names none */
export const randomGeneratorSchema = z.object({
  type: z.literal('random'),
  bytes: z.int().min(16).max(64).default(32),
  encoding: z.enum(SECRET_ENCODINGS).default('hex'),
  prefix: z.string().regex(SECRET_PREFIX_PATTERN, 'prefix may only hold letters, digits, dashes and underscores').default(''),
}).strict()

/** The bcrypt hash of `input`, a random generate key of the same manifest: a derived value that follows its input */
export const bcryptGeneratorSchema = z.object({
  type: z.literal('bcrypt'),
  input: secretKeySchema,
  rounds: z.int().min(BCRYPT_ROUNDS.min).max(BCRYPT_ROUNDS.max).default(BCRYPT_ROUNDS.default),
}).strict()

/** How `setup` produces a generate secret; a new way is one more member here and one case in ../utils/generators.ts */
export const generatorSchema = z.discriminatedUnion('type', [randomGeneratorSchema, bcryptGeneratorSchema])

/** A value `setup` writes; rotation says what changing it later costs (see ../../../../SPEC.md) */
export const generateSecretSchema = z.object({
  source: z.literal('generate'),
  description: descriptionSchema,
  rotation: z.enum(SECRET_ROTATIONS).default('free'),
  file: z.enum(SECRET_FILES).default('.env'),
  // prefault, not default: the defaults of the random generator are applied to it
  generator: generatorSchema.prefault({ type: 'random' }),
  related: relatedSchema.optional(),
}).strict()

/** A value a human sets with `secrets set`; required only under the listed root .env values, optional without them */
export const promptSecretSchema = z.object({
  source: z.literal('prompt'),
  description: descriptionSchema,
  required: secretRequiredSchema.optional(),
  related: relatedSchema.optional(),
}).strict()

/** A copy of a generate or prompt secret of another directory, `from` relative to this manifest */
export const linkSecretSchema = z.object({
  source: z.literal('link'),
  from: z.string().min(1, 'from must not be empty').refine(from => !from.startsWith('/'), 'from is a directory relative to the manifest'),
  key: secretKeySchema,
}).strict()

export const secretEntrySchema = z.discriminatedUnion('source', [generateSecretSchema, promptSecretSchema, linkSecretSchema])

/** The shape of a .env.json next to a .env.template, mirrored for editors by compose/.env.schema.json */
export const secretsManifestSchema = z.object({
  $schema: z.string().optional(),
  secrets: z.record(secretKeySchema, secretEntrySchema).refine(secrets => Object.keys(secrets).length > 0, 'secrets must not be empty'),
}).strict()

export type RandomGenerator = z.infer<typeof randomGeneratorSchema>
export type BcryptGenerator = z.infer<typeof bcryptGeneratorSchema>
export type Generator = z.infer<typeof generatorSchema>
export type GenerateSecret = z.infer<typeof generateSecretSchema>
export type PromptSecret = z.infer<typeof promptSecretSchema>
export type LinkSecret = z.infer<typeof linkSecretSchema>
export type SecretEntry = z.infer<typeof secretEntrySchema>
export type SecretRequired = z.infer<typeof secretRequiredSchema>
export type SecretsManifest = z.infer<typeof secretsManifestSchema>
