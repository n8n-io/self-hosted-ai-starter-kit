# n8n Hooks

Backend hooks that extend n8n at runtime using the `EXTERNAL_HOOK_FILES` mechanism. The main deliverable is a custom REST API mounted at `/api-custom/v1` that adds endpoints not available in the standard n8n public API, using the same authentication as n8n's built-in public API.

---

## Getting Started

### Run with Docker Compose

Run from the **repository root**:

```bash
docker compose up
```

---

## Project Structure

```text
hooks/
├── insomnia.yaml                   # Insomnia API collection for all /api-custom/v1 endpoints
├── backend/
│   ├── hooks.js                    # Main backend hook entrypoint (loaded via EXTERNAL_HOOK_FILES)
│   ├── inject-frontend-hook.js     # Serves & injects the frontend hook script
│   ├── embed-login-hook.js         # Registers GET /rest/embed/login — issues a session cookie for the owner and redirects to the n8n UI
│   ├── workflow-update-hook.js     # Logs workflow update events via the n8n.workflow.update hook
│   ├── api/
│   │   ├── add-api-hook.js         # Registers the /api-custom/v1 router on n8n.ready
│   │   ├── router.js               # Route definitions
│   │   ├── middleware.js           # Auth & error handling middleware
│   │   ├── owner.js                # Owner setup & retrieval handlers
│   │   ├── api-keys.js             # API key management handlers
│   │   ├── jwt-token.js            # JWT token issuance handler
│   │   ├── settings.js             # SSO settings handlers
│   │   ├── workflows.js            # Workflow validation handler
│   │   └── test.js                 # Test endpoint handlers
│   └── utils/
│       ├── di.js                   # Loads n8n internal services via dependency injection
│       ├── router.js               # injectMiddleware() / injectApiRouter() helpers
│       ├── middleware.js           # Express middleware utilities
│       ├── scopes.js               # API key scope helpers
│       ├── date.js                 # Date utilities
│       ├── user.js                 # User repository queries
│       ├── roles.js                # Role validation
│       ├── merge.js                # Hook object merging
│       ├── stream.js               # HTML response stream injection
│       ├── path.js                 # HTML path detection
│       ├── file.js                 # File loading with caching
│       ├── json.js                 # Safe JSON stringify
│       └── npm.js                  # npm package path resolution
├── frontend/
│   └── hooks.js                    # Frontend hook (runs in the browser)
└── _examples/                      # Additional hook examples
```

---

## The `/api-custom/v1` API

The hook registers a custom Express router at `/api-custom/v1` when n8n starts. Authenticated routes use the same `x-n8n-api-key` header as the standard n8n public API — the middleware validates the JWT using n8n's `PublicApiKeyService` and requires the caller to have the `global:owner` role.

### Authentication

Pass your n8n API key in the request header:

```http
x-n8n-api-key: <your-n8n-api-key>
```

Returns `401 Unauthorized` if the key is missing, invalid, or the user is not an instance owner.

---

### Endpoints

#### Test

| Method | Path | Auth | Description |
| - | - | - | - |
| `GET` | `/api-custom/v1/test` | No | Public health check — returns `{ success: true }` |
| `GET` | `/api-custom/v1/test-auth` | Yes | Authenticated health check — returns `{ success: true }` |

#### Owner

| Method | Path | Auth | Description |
| - | - | - | - |
| `POST` | `/api-custom/v1/owner/setup` | No | Set up the n8n instance owner. Creates the owner account and returns a master API key with a 99-year expiration. Body: `{ email, firstName, lastName, password }` |
| `GET` | `/api-custom/v1/owner` | Yes | Returns the current instance owner |

#### API Keys

| Method | Path | Auth | Description |
| - | - | - | - |
| `GET` | `/api-custom/v1/users/:id/api-keys` | Yes | List API keys for a user (redacted) |
| `POST` | `/api-custom/v1/users/:id/api-keys` | Yes | Create a new API key for a user. Body: `{ label, expiresAt, scopes? }` |

#### JWT Token

| Method | Path | Auth | Description |
| - | - | - | - |
| `GET` | `/api-custom/v1/users/:id/jwt-token` | Yes | Issue a JWT session token for a user. Returns `{ jwt }`. Returns `400` if the user does not exist. |

#### Workflows

| Method | Path | Auth | Description |
| - | - | - | - |
| `POST` | `/api-custom/v1/workflows/validate` | Yes | Validate a workflow for activation. Body: `{ workflow: { nodes, connections } }`. Returns the validation result. Returns `400` if `workflow`, `nodes`, or `connections` are missing. |

#### Settings — SSO

| Method | Path | Auth | Description |
| - | - | - | - |
| `GET` | `/api-custom/v1/settings/sso` | Yes | Get current SAML and OIDC SSO configuration |
| `POST` | `/api-custom/v1/settings/sso/saml` | Yes | Update SAML configuration. Body: `{ metadataUrl, loginEnabled }` |
| `POST` | `/api-custom/v1/settings/sso/oidc` | Yes | Update OIDC configuration. Body: `{ clientId, clientSecret, discoveryEndpoint, ... }` |

---

## API Development with Insomnia

The repo includes [insomnia.yaml](insomnia.yaml) — an Insomnia collection with a request for every endpoint above, pre-configured with environment variables:

- `url` — defaults to `http://localhost:5678/api-custom/v1`
- `api-key` — your n8n API key for authenticated requests

Import `insomnia.yaml` into [Insomnia](https://insomnia.rest/) to get started immediately without manual setup.

---

## Utils: `di.js`

[backend/utils/di.js](backend/utils/di.js) provides typed accessors for n8n's internal services via its dependency injection container (`@n8n/di` or `typedi`). Rather than reaching into n8n internals directly, route handlers call functions like `getOwnershipService()` or `getPublicApiKeyService()` to get fully initialized service instances at request time. Results are memoized. If a service fails to load (e.g. because an Enterprise feature is not licensed), the error is logged and the accessor returns `undefined`.

Available accessors:

| Function | Returns |
|----------|---------|
| `getOwnershipService()` | `OwnershipService` |
| `getUserService()` | `UserService` |
| `getUserRepository()` | `UserRepository` |
| `getPublicApiKeyService()` | `PublicApiKeyService` |
| `getAuthService()` | `AuthService` |
| `getLicense()` | `License` |
| `getSsoOidcService()` | `OidcService` (EE) |
| `getSsoSamlService()` | `SamlService` (EE) |
| `getInstanceSettings()` | `InstanceSettings` |
| `getWorkflowValidationService()` | `WorkflowValidationService` |
| `getNodeTypesService()` | `NodeTypes` |
| `getUrlService()` | `UrlService` |

---

## Frontend Hook

The backend serves `frontend/hooks.js` at `/rest/frontend-hook.js` and injects a `<script>` tag into every HTML response, so the hook runs in the browser without any changes to the n8n frontend build.

```js
// frontend/hooks.js
window.n8nExternalHooks = {
  app: {
    mount: [function (store, meta) { /* ... */ }],
  },
};
```
