# Interactive prompts

Paths are relative to `packages/cli/`.

- Primitives: `text`, `select`, `multiselect`, `confirm`, `password` (secrets, masked) from `@clack/prompts`. Every result is checked with `isCancel`; a cancel logs `logger.cancel(...)` and returns without writing.
- `config` runs at most two prompts: the key select (only without `KEY`) and the prompt of that key (`promptDomain`, `promptChoice` in `src/commands/config.ts`, each returning `undefined` on cancel; for `AI_MODELS` the second one is the prompt of `models select`). `models select` runs one prompt, `promptModels` in `src/commands/models.ts`. With a value on the command line no prompt runs at all.
- `text` validation delegates to a zod schema (`domainSchema.safeParse(value).error?.issues[0]?.message`), so error messages live in the schema.
- `select` options come straight from the schema tuples (`N8N_VARIANTS.map(value => ({ value, label: value }))`) with `initialValue` parsed from the current file, so an invalid current value falls back to the first option.
- A clack `hint` shows on the focused row only: what must stay visible on every row goes into the label, as the green `(detected)` of `AI_RUNTIME` does.
- `modelOptions(catalogue, engine, runtime, { memory })` builds the multiselect: `value` and `label` are the id, the `hint` joins label, engine model name, the memory as `formatMemory()` renders it (`~6 GB RAM`, `VRAM` on a `gpu-*` runtime), a yellow `over the <N> GB of docker memory` when the estimate exceeds the detected docker memory on a cpu runtime, the note and a yellow `not on <runtime>` when disabled (`styleText` stays plain without a TTY or with `NO_COLOR`); `required: false`; `initialValues` are the ids of the current `AI_MODELS` that are enabled.
- After the selection, `models select` prints the endpoints n8n uses (`logModelEndpoints`): `http://ollama:11434`, or `http://vllm-<id>:8000/v1` plus the `VLLM_API_KEY` note per model, the id being the `id` of the catalogue entry (`vllmContainerName` mirrors the vllm compose `container_name`).
- Tests mock `@clack/prompts` wholesale and drive each prompt function per test: see "Testing practices" in [SKILL.md](../SKILL.md).
