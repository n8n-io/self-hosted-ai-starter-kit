const { Router } = require("express");
const { createAuthMiddleware, createErrorMiddleware } = require("./middleware");
const { testPublic, testAuthenticated } = require("./test");
const { setupOwner, getOwner } = require("./owner");
const { listApiKeys, createApiKey } = require("./api-keys");
const { createJwtToken } = require("./jwt-token");
const { validateWorkflow } = require("./workflows");
const {
  getSsoSetting,
  createSsoOIDCSetting,
  createSsoSamlSetting,
} = require("./settings");

const authMiddleware = createAuthMiddleware();

function createApiRouter() {
  const router = Router();

  // GET /api-custom/v1/setup
  router.get("/test", testPublic);
  // POST /api-custom/v1/owner/setup
  router.post("/owner/setup", setupOwner);

  // All routes below require authentication
  router.use(authMiddleware);

  // GET /api-custom/v1/test-auth
  router.get("/test-auth", testAuthenticated);
  // GET /api-custom/v1/owner
  router.get("/owner", getOwner);

  // GET /api-custom/v1/users/:id/api-keys
  router.get("/users/:id/api-keys", listApiKeys);
  // POST /api-custom/v1/users/:id/api-keys
  router.post("/users/:id/api-keys", createApiKey);

  // GET /api-custom/v1/users/:id/jwt-token
  router.get("/users/:id/jwt-token", createJwtToken);

  // GET /api-custom/v1/settings/sso
  router.get("/settings/sso", getSsoSetting);
  // POST /api-custom/v1/settings/sso/saml
  router.post("/settings/sso/saml", createSsoSamlSetting);
  // POST /api-custom/v1/settings/sso/oidc
  router.post("/settings/sso/oidc", createSsoOIDCSetting);

  // POST /api-custom/v1/workflows/validate
  router.post("/workflows/validate", validateWorkflow);

  router.use(createErrorMiddleware());

  return router;
}

module.exports = { createApiRouter };
