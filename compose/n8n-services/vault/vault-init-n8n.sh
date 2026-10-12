#!/usr/bin/env sh

# install jq
apk add jq

# login with the root token (pass it in with `-e VAULT_TOKEN=...`)
vault login "${VAULT_TOKEN:?VAULT_TOKEN is required}" > /dev/null

# Enable the KV v2 store and AppRole auth if they are not enabled yet
vault secrets list -format=json | jq -e '."kv/"' > /dev/null || vault secrets enable -path=kv kv-v2
vault auth list -format=json | jq -e '."approle/"' > /dev/null || vault auth enable approle

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