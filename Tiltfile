version_settings(constraint='>=0.37.7')
docker_prune_settings ( disable = False , max_age_mins = 360 , num_builds = 0 , interval_hrs = 1 , keep_recent = 2 )


# Extensions
# https://github.com/tilt-dev/tilt-extensions/tree/master/dotenv
load('ext://dotenv', 'dotenv')
# https://github.com/tilt-dev/tilt-extensions/tree/master/base64
# https://github.com/tilt-dev/tilt-extensions/tree/master/global_vars
# https://github.com/tilt-dev/tilt-extensions/tree/master/wait_for_it

def hi():
  print("✨ Tilt runs n8n self-hosted-ai-starter-kit !")


# DOTENV
dotenv(fn='./.env', verbose=True, showValues=True)
DOMAIN = str(os.getenv('DOMAIN')) 

# PARSE tilt up args
config.define_string_list("to-run", args=False)
cfg = config.parse()

TO_RUN = cfg.get('to-run', [])

print("DOMAIN:", DOMAIN)
print("TO_RUN:", TO_RUN)

hi()

groups = {
  'traefik': ['network traefik', 'certs', 'docker-socket-proxy', 'traefik', 'whoami'],
  'postgres': ['network postgres', 'postgres', 'pgadmin'],
  'redis': ['network redis', 'redis', 'redisinsight'],
  'garage': ['network garage', 'garage', 'garage-webui'],
  'vault': ['network vault', 'vault', 'vault-unseal'],
}
resources = []
for arg in TO_RUN:
  if arg in groups:
    resources += groups[arg]
  else:
    # also support specifying individual services instead of groups, e.g. `tilt up a b d`
    resources.append(arg)
config.set_enabled_resources(resources)

# NETWORKS
local_resource('network traefik', cmd='./scripts/network.sh traefik', allow_parallel=False, labels=["proxy"])
local_resource('network postgres', cmd='./scripts/network.sh postgres', allow_parallel=False, labels=["n8n-data"])
local_resource('network redis', cmd='./scripts/network.sh redis', allow_parallel=False, labels=["n8n-data"])
local_resource('network garage', cmd='./scripts/network.sh garage', allow_parallel=False, labels=["n8n-data"])
local_resource('network vault', cmd='./scripts/network.sh vault', allow_parallel=False, labels=["n8n-services"])
local_resource('network n8n', cmd='./scripts/network.sh n8n', allow_parallel=False, labels=["n8n"])

# CERTS: local TLS cert for *.dev.localhost (mkcert), created once into ~/.certs/dev
local_resource('certs', cmd='test -f "$HOME/.certs/dev/cert.pem" || ./scripts/cert.sh', allow_parallel=False, labels=["proxy"])

# TRAEFIK
docker_compose(['./compose/proxy/docker-socket-proxy/docker-compose.yml'])
dc_resource('docker-socket-proxy', labels=["proxy"], resource_deps=['network traefik'])
docker_compose(['./compose/proxy/traefik/docker-compose.yml'])
dc_resource('traefik', labels=["proxy"], resource_deps=['network traefik', 'certs'], links=['traefik.' + DOMAIN], infer_links=False)

# TRAEFIK WHOAMI
docker_compose(['./compose/proxy/whoami/docker-compose.yml'])
dc_resource('whoami', labels=["proxy"], resource_deps=['network traefik'], links=['whoami.' + DOMAIN], auto_init=True)

# POSTGRES
docker_compose(['./compose/n8n-data/postgres/docker-compose.yml'])
dc_resource('postgres', labels=["n8n-data"], resource_deps=['network postgres'], infer_links=False)
# PGADMIN
docker_compose(['./compose/n8n-data/pgadmin/docker-compose.yml'])
dc_resource('pgadmin', labels=["n8n-data"], resource_deps=['network traefik', 'network postgres', 'postgres'], links=['pgadmin.' + DOMAIN], auto_init=False)

# REDIS
docker_compose(['./compose/n8n-data/redis/docker-compose.yml'])
dc_resource('redis', labels=["n8n-data"], resource_deps=['network redis'], infer_links=False, auto_init=False)
# REDIS INSIGHT
docker_compose(['./compose/n8n-data/redis-insight/docker-compose.yml'])
dc_resource('redisinsight', labels=["n8n-data"], resource_deps=['network traefik', 'network redis', 'redis'], links=['redisinsight.' + DOMAIN], auto_init=False)

# GARAGE
docker_compose(['./compose/n8n-data/garage/docker-compose.yml'])
dc_resource('garage', labels=["n8n-data"], resource_deps=['network garage'], links=['s3.' + DOMAIN, 'web.' + DOMAIN], auto_init=False)
dc_resource('garage-webui', labels=["n8n-data"], resource_deps=['network garage'], links=['s3ui.' + DOMAIN], auto_init=False)

# VAULT
docker_compose(['./compose/n8n-services/vault/docker-compose.yml'])
dc_resource('vault', labels=["n8n-services"], resource_deps=['network vault'], links=['vault.' + DOMAIN], auto_init=False)
dc_resource('vault-unseal', labels=["n8n-services"], resource_deps=['vault'], infer_links=False, auto_init=False)

# n8n
docker_compose(['./compose/n8n/docker-compose.yml'])
dc_resource('n8n', labels=["n8n"], resource_deps=['postgres'], links=['n8n.' + DOMAIN])
dc_resource('n8n-runner', labels=["n8n"], resource_deps=['n8n'])


## AI MODELS
# All ai-models files live in one docker_compose call: Tilt drops the services of a second call from the same directory.
# The runtimes and ollama files run on the runtime selected by AI_RUNTIME (cpu-x86-64 | cpu-arm64 | gpu-nvidia | gpu-amd).
# apple-silicon runs Ollama natively on the host instead: Docker on macOS cannot reach the Metal GPU.
AI_RUNTIME = str(os.getenv('AI_RUNTIME'))
OLLAMA_SERVICES = {'cpu-x86-64': 'cpu', 'cpu-arm64': 'cpu', 'dgx-spark': 'gpu-nvidia', 'gpu-nvidia': 'gpu-nvidia', 'gpu-amd': 'gpu-amd'}
OLLAMA = OLLAMA_SERVICES.get(AI_RUNTIME, 'cpu')
docker_compose(['./compose/ai-models/docker-compose.vllm.yml', './compose/ai-models/docker-compose.vllm-runtimes.yml', './compose/ai-models/docker-compose.ollama.yml'], profiles=['nemotron-3-embed', 'nemotron-3-nano-omni-30b', 'nemotron-3-content-safety', 'nemotron-parse', AI_RUNTIME])
dc_resource('vllm-nvidia-nemotron-3-embed', labels=["ai-models"], resource_deps=['network n8n'], auto_init=False)
# dc_resource('vllm-nvidia-nemotron-3-nano-omni-30b-a3b-reasoning-nvfp4', labels=["ai-models"], auto_init=False)
# dc_resource('vllm-nvidia-nemotron-3-content-safety', labels=["ai-models"], auto_init=False)
# dc_resource('vllm-nvidia-nemotron-parse', labels=["ai-models"], auto_init=False)
if AI_RUNTIME == 'apple-silicon':
  # Reachable from containers at http://host.docker.internal:11434. Reuses an Ollama that is already running (app or `brew services`).
  local_resource('ollama-apple-silicon', serve_cmd='curl -sf http://localhost:11434 > /dev/null && exec tail -f /dev/null || exec ollama serve', readiness_probe=probe(http_get=http_get_action(11434, path='/')), labels=["ai-models"], auto_init=False)
  local_resource('ollama-pull-llama-apple-silicon', cmd='ollama pull llama3.2', resource_deps=['ollama-apple-silicon'], labels=["ai-models"], auto_init=False)
else:
  dc_resource('vllm-' + AI_RUNTIME, labels=["ai-models"], resource_deps=['network n8n'], auto_init=False)
  dc_resource('ollama-' + OLLAMA, labels=["ai-models"], resource_deps=['network n8n'], auto_init=False)
  dc_resource('ollama-pull-llama-' + OLLAMA, labels=["ai-models"], resource_deps=['ollama-' + OLLAMA], auto_init=False)

## AI SERVICES
docker_compose(['./compose/ai-services/qdrant/docker-compose.yml'])
dc_resource('qdrant', labels=["ai-services"], resource_deps=['network n8n'], auto_init=False)
docker_compose(['./compose/ai-services/litellm/docker-compose.yml'])
dc_resource('litellm', labels=["ai-services"], resource_deps=['network n8n', 'network traefik'], links=['litellm.' + DOMAIN], auto_init=False)
dc_resource('db', new_name='litellm-db', labels=["ai-services"], resource_deps=['network n8n'], auto_init=False)  # litellm waits for it: trigger litellm-db, then litellm