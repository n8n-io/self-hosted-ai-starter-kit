import { z } from 'zod'
import { AI_RUNTIMES, configSchema } from './config'
import { modelIdSchema } from './models'

/** The compose directories, the Tilt UI groups resources by them (see ../../../../SPEC.md) */
export const COMPOSE_GROUPS = ['proxy', 'n8n', 'storage', 'services', 'models'] as const

/** One dc_resource() call; the keys are its keyword arguments, `service` its name and `enabled` the config.set_enabled_resources() membership */
export const tiltResourceSchema = z.object({
  /** The compose service, the name dc_resource() configures */
  service: z.string().min(1),
  /** The Tilt resource name: the service, or the new_name of a model server (`ollama`, `vllm-<id>`) */
  name: z.string().min(1),
  labels: z.array(z.enum(COMPOSE_GROUPS)).min(1),
  resource_deps: z.array(z.string()),
  links: z.array(z.string()),
  infer_links: z.boolean(),
  auto_init: z.boolean(),
  enabled: z.boolean(),
}).strict()

/** One docker_compose() call and the resources it registers */
export const tiltProjectSchema = z.object({
  /** Compose files relative to the Tiltfile, the last one is the entry point */
  files: z.array(z.string().min(1)).min(1),
  /** Files that reload Tilt when edited: the .env beside the entry file, which Tilt does not watch by itself, and the parents of the n8n cascade */
  watch: z.array(z.string().min(1)),
  /** The compose project name when it differs from the `name:` of the file (`ollama`, `vllm-<id>`) */
  project_name: z.string().min(1).optional(),
  profiles: z.array(z.enum(AI_RUNTIMES)),
  /** An inline compose override of the files, passed through encode_yaml() (the model injection) */
  override: z.record(z.string(), z.unknown()).optional(),
  /** The `secrets read` filter of the project, its directory, when a .env.secrets.json sits beside the entry file: every resource gets a secrets button */
  secrets: z.string().min(1).optional(),
  resources: z.array(tiltResourceSchema).min(1),
}).strict()

/** The output of `tilt resources`: the validated root .env and every compose project the Tiltfile registers */
export const tiltResourcesSchema = z.object({
  config: configSchema.extend({ AI_MODELS: z.array(modelIdSchema) }).strict(),
  projects: z.array(tiltProjectSchema),
}).strict().superRefine((plan, ctx) => {
  const resources = plan.projects.flatMap(project => project.resources)
  const names = new Set<string>()
  for (const resource of resources) {
    if (names.has(resource.name))
      ctx.addIssue({ code: 'custom', message: `Duplicate Tilt resource "${resource.name}"` })
    names.add(resource.name)
  }
  const enabled = new Set(resources.filter(resource => resource.enabled).map(resource => resource.name))
  for (const resource of resources) {
    for (const dep of resource.resource_deps) {
      if (!names.has(dep))
        ctx.addIssue({ code: 'custom', message: `Resource "${resource.name}" depends on unknown resource "${dep}"` })
      else if (resource.enabled && !enabled.has(dep))
        ctx.addIssue({ code: 'custom', message: `Enabled resource "${resource.name}" depends on disabled resource "${dep}"` })
    }
  }
})

export type ComposeGroup = typeof COMPOSE_GROUPS[number]
export type TiltResource = z.infer<typeof tiltResourceSchema>
export type TiltProject = z.infer<typeof tiltProjectSchema>
export type TiltResources = z.infer<typeof tiltResourcesSchema>
