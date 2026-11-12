version_settings(constraint='>=0.37.7')
docker_prune_settings ( disable = False , max_age_mins = 360 , num_builds = 0 , interval_hrs = 1 , keep_recent = 2 )

# Load .env file: the compose projects inherit DOMAIN from it (see ./SPEC.md)
load('ext://dotenv', 'dotenv')
dotenv(fn='./.env', verbose=True, showValues=True)

include('ext://cancel')

load('ext://uibutton', 'cmd_button')

# The n8n-starter cli (./packages/cli) gates and plans this Tiltfile: `verify` checks the tool versions, the .env
# files and networks, `tilt resources` turns the root .env and ./compose/models/models.json into the compose
# projects to register, which resources to enable and which to auto-start (see ./SPEC.md and
# ./packages/cli/src/commands/tilt.ts). The Tiltfile only loops over that plan.
CLI = 'packages/cli/dist/index.mjs'

def print_hi():
  print("✨ Tilt runs n8n self-hosted-ai-starter-kit !")

def print_env(cfg):
  print("📦 N8N_VARIANT:", cfg['N8N_VARIANT'])
  print("🧠 AI_RUNTIME:", cfg['AI_RUNTIME'])
  print("🤖 AI_ENGINE:", cfg['AI_ENGINE'])
  print("🚪 AI_GATEWAY:", cfg['AI_GATEWAY'] or '(none)')
  print("🧩 AI_MODELS:", ', '.join(cfg['AI_MODELS']) or '(none)')
  print("🌐 DOMAIN:", cfg['DOMAIN'])

def verify():
  # The gate: `verify --json` reports the tool versions, the .env files, the secrets and the docker networks (see ./SPEC.md). local()
  # cannot read an exit code and raises on exit 1, so `|| true` keeps it quiet and `ok` of the report decides:
  # its warnings become Tilt alerts, its errors (❌) and hints (💡) one fail() instead of a traceback.
  if not os.path.exists(CLI):
    fail('n8n-starter cli is not built (%s is missing). Run `pnpm run build` first.' % CLI)
  out = str(local('node %s verify --json || true' % CLI, echo_off=True, quiet=True)).strip()
  if not out:
    fail('`node %s verify --json` printed no report, see the log above.' % CLI)
  report = decode_json(out)
  for message in report['warnings']:
    warn(message)
  if not report['ok']:
    fail('\n'.join(['The environment is not ready:'] + ['  ❌ ' + line for line in report['errors']] + ['  💡 ' + line for line in report['hints']]))

def load_plan():
  # The resource plan as JSON; an invalid root .env or an AI_MODELS id the engine does not serve on the
  # runtime fails the command, and with it the Tiltfile, with the reason. quiet=True keeps the JSON out
  # of the log. The plan is built from the root .env and the catalogue, so edits to them reload Tilt.
  watch_file('./.env')
  watch_file('./compose/models/models.json')
  return decode_json(local('node %s tilt resources --log-level error' % CLI, echo_off=True, quiet=True))

def watch_plan(plan):
  # The .env beside every entry file and the cascade parents, registered before the verify() gate: Tilt keeps the
  # paths recorded before a fail(), so a `pnpm run setup` or `pnpm run secrets set` that fixes the gate reloads
  # the Tiltfile by itself (see ./SPEC.md)
  for p in plan['projects']:
    for f in p['watch']:
      watch_file(f)

def apply_enabled_resources(enabled):
  # disable all resources by default, then enable the ones of the plan
  config.clear_enabled_resources()
  config.set_enabled_resources(enabled)
  # On a reload Tilt keeps the old enabled/disabled flags unless `tilt args` changed (tilt-dev/tilt#6800), and the
  # set comes from the root .env here, so re-apply it for the already registered resources (see ./SPEC.md).
  # Nothing is registered on the first load and no API server runs for `tilt down` or `tilt alpha tiltfile-result`.
  if config.tilt_subcommand != 'up':
    return
  out = str(local('tilt get uiresources -o name 2>/dev/null || true', quiet=True, echo_off=True))
  existing = [line.split('/', 1)[1] for line in out.splitlines() if '/' in line and not line.endswith('(Tiltfile)')]
  wanted = [name for name in enabled if name in existing]
  if not wanted:
    return
  cmd = 'tilt enable --only %s || echo TILT_ENABLE_FAILED' % ' '.join(wanted)
  if 'TILT_ENABLE_FAILED' in str(local(cmd, quiet=True, echo_off=True)):
    warn('Could not re-apply the enabled resources after the reload, run `tilt enable --only %s` by hand' % ' '.join(wanted))

print_hi()
plan = load_plan()
watch_plan(plan)
verify()
print_env(plan['config'])
apply_enabled_resources([r['name'] for p in plan['projects'] for r in p['resources'] if r['enabled']])


 

# one docker_compose() per project (the model servers carry an inline override, see ./SPEC.md) and one
# dc_resource() per resource; disabled services stay registered so they show up in the UI
for p in plan['projects']:
  files = p['files'] + ([encode_yaml(p['override'])] if 'override' in p else [])
  project_name = p.get('project_name', '')
  docker_compose(files, project_name=project_name, profiles=p['profiles'])
  for r in p['resources']:
    dc_resource(
      r['service'],
      project_name=project_name,
      new_name=r['name'] if r['name'] != r['service'] else '',
      labels=r['labels'],
      resource_deps=r['resource_deps'],
      links=r['links'],
      infer_links=r['infer_links'],
      auto_init=r['auto_init'],
    )
    # a project with a .env.secrets.json: a button per resource prints its secrets into the resource log (see ./SPEC.md)
    if 'secrets' in p:
      cmd_button('%s-secrets' % r['name'], resource=r['name'], argv=['node', CLI, 'secrets', 'read', p['secrets']], icon_name='key', text='secrets')
