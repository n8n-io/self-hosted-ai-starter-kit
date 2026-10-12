# n8n External Secrets with HashiCorp Vault

n8n stores all credentials encrypted in its database and restricts access to them by default. With the [external secrets feature](https://docs.n8n.io/external-secrets/), you can store sensitive credential information in an external vault and have n8n load it when required. This provides an extra layer of security and allows you to manage credentials used across multiple n8n environments in one central place.

## How n8n Reads Secrets

n8n supports reading secrets from KV stores. Once connected, all readable secrets are periodically fetched and instantly available when workflows execute (see [Caching](#how-n8n-caches-secrets)). n8n supports token and userpass authentication, but [AppRole](https://developer.hashicorp.com/vault/docs/auth/approle) authentication is recommended.

## What Policies n8n Needs

n8n scans all KV stores recursively for readable secrets and requires at least:

| Path          	| Capability 	| Reason          	|
|---------------	|------------	|-----------------	|
| sys/mounts    	| read       	| find KV stores  	|
| kv/metadata/* 	| list       	| list KV secrets 	|
| kv/data/*     	| read       	| read KV secrets 	|

You can further limit access to secrets within KV stores, e.g., only allow access to secrets under the subpath `n8n/*` within a KV store.

| Path              	| Capability 	| Reason                           	|
|-------------------	|------------	|----------------------------------	|
| sys/mounts        	| read       	| find KV stores                   	|
| kv/metadata/      	| list       	| list KV root paths for recursion 	|
| kv/metadata/n8n/* 	| list       	| list KV subpath secrets & paths  	|
| kv/data/n8n/*     	| read       	| read KV subpath secrets          	|

## How n8n Caches Secrets

n8n will fetch all available secrets periodically (default 5 minutes) and cache them for instant access when workflows execute.

| Environment Variable                               	| Type   	| Default          	| Description                                         	|
|------------------------------------------------------	|--------	|------------------	|-----------------------------------------------------	|
| `N8N_EXTERNAL_SECRETS_UPDATE_INTERVAL` 	| number 	| 300  (5 minutes) 	| How often (in seconds) to check for secret updates. 	|

### Vault API Request Limits

Each cache update creates a burst of HashiCorp Vault API requests to find all secrets recursively and read the secrets data. In case your HashiCorp Vault instance has rigid API limits, increase `N8N_EXTERNAL_SECRETS_UPDATE_INTERVAL` to reduce the total number of API requests within limit windows. The number of API calls n8n will make on each cache update includes:

* 1 to read sys/mounts
* 1 for each KV store
* 1 for each path segment within a KV store (recursion)
* 1 for each secret within a KV store

> Example: For 1 KV store without any subpath (flat) including 100 secrets, the total number would be ~102 API calls.

## Local setup (first start)

A fresh Vault is uninitialized and sealed, so `vault-unseal` has nothing to unseal until you initialize it once. Start the `vault` resource in Tilt (or `docker compose up -d vault` here), then from this directory:

```sh
# 1. Initialize once; save the unseal key and root token somewhere safe
docker compose exec vault vault operator init -key-shares=1 -key-threshold=1

# 2. Put the unseal key into .env (created from .env.template by `pnpm run setup`)
#    VAULT_UNSEAL_KEY=<Unseal Key 1>

# 3. Start the vault-unseal resource (it unseals Vault now and after every restart)
docker compose up -d vault-unseal

# 4. Create the KV store, AppRole, policy and entity for n8n; prints RoleId and SecretId
docker compose exec -e VAULT_TOKEN=<Initial Root Token> vault sh /home/vault/vault-init-n8n.sh
```

Never commit the unseal key or root token. A single key share is for local development only.

## Tutorial: Setup AppRole and Policy using Vault CLI 

> <font color="yellow">Work in Progress</font>

* The AppRole auth method enables machines or apps to authenticate.
* An AppRole's RoleID and SecretID are like a username and password that a machine or app uses to authenticate.

```sh

# Create Policy
vault policy write n8n -<<EOF
# Needs list metadata access to find/list/cache all readable secrets
path "kv/metadata/*" {
  capabilities = ["list"] 
}

# Needs read data access to read secret values
path "kv/data/*" {
  capabilities = ["read"] 
}

# Needs sys/mounts read access to find readable kv stores
path "sys/mounts" {
  capabilities = ["read"]
}
EOF

# Create AppRole
vault write auth/approle/role/n8n token_policies="n8n" secret_id_ttl=999999999 secret_id_num_uses=999999999
# Read RoleID
ROLE_ID=$(vault read auth/approle/role/n8n/role-id -format=json | jq -r .data.role_id)
# Create SecretID
SECRET_ID=$(vault write -force auth/approle/role/n8n/secret-id -format=json | jq -r .data.secret_id)


# Get Accessor ID
ACCESSOR_ID=$(vault auth list -format=json | jq -r '.["approle/"].accessor')
# Create Entity
ENTITY_ID=$(vault write identity/entity name="n8n" policies="n8n" -format=json | jq -r ".data.id")
# Create Entity Alias
vault write identity/entity-alias name="n8n" canonical_id="$ENTITY_ID" mount_accessor="$ACCESSOR_ID"

echo ""
echo "### Finished"
echo "Policy: n8n"
echo "Entity: n8n"
echo "AppRole: n8n"
echo "RoleId: $ROLE_ID"
echo "SecretId: $SECRET_ID"
```