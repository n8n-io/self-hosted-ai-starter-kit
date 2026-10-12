const path = require("path");

let diPackage;

try {
  diPackage = require("@n8n/di");
} catch {
  diPackage = require("typedi");
}

if (!diPackage) {
  throw new Error("No DI container package found. Aborting");
}

const Container = diPackage.Container;

let license;

let ownershipService;
let userService;
let userRepository;
let authService;

let nodeTypesService;
let urlService;
let workflowValidationService;

let oidcService;
let samlService;

let instanceSettings;
let publicApiKeyService;
let apiKeyAuthStrategy;

/**
 * https://github.com/n8n-io/n8n/blob/master/packages/cli/src/services/ownership.service.ts
 * @returns OwnershipService
 */
function getOwnershipService() {
  if (ownershipService) return ownershipService;
  try {
    const { OwnershipService } = require("n8n/dist/services/ownership.service");
    ownershipService = Container.get(OwnershipService);
  } catch (error) {
    console.error("Error loading Ownership Service:", error);
    return;
  }
  return ownershipService;
}

/**
 * https://github.com/n8n-io/n8n/blob/master/packages/cli/src/services/user.service.ts
 * @returns UserService
 */
function getUserService() {
  if (userService) return userService;
  try {
    const { UserService } = require("n8n/dist/services/user.service");
    userService = Container.get(UserService);
  } catch (error) {
    console.error("Error loading User Service:", error);
    return;
  }
  return userService;
}

/**
 * https://github.com/n8n-io/n8n/blob/master/packages/%40n8n/db/src/repositories/user.repository.ts
 * @returns UserRepository
 */
function getUserRepository() {
  if (userRepository) return userRepository;
  try {
    const { UserRepository } = require("@n8n/db");
    userRepository = Container.get(UserRepository);
  } catch (error) {
    console.error("Error loading User Repository:", error);
    return;
  }
  return userRepository;
}

/**
 * https://github.com/n8n-io/n8n/blob/master/packages/cli/src/services/public-api-key.service.ts
 * @returns PublicApiKeyService
 */
function getPublicApiKeyService() {
  if (publicApiKeyService) return publicApiKeyService;
  try {
    const {
      PublicApiKeyService,
    } = require("n8n/dist/services/public-api-key.service");
    publicApiKeyService = Container.get(PublicApiKeyService);
  } catch (error) {
    console.error("Error loading Public Api Key Service:", error);
    return;
  }
  return publicApiKeyService;
}

/**
 * https://github.com/n8n-io/n8n/blob/master/packages/cli/src/services/api-key-auth.strategy.ts
 * @returns ApiKeyAuthStrategy
 */
function getApiKeyAuthStrategy() {
  if (apiKeyAuthStrategy) return apiKeyAuthStrategy;
  try {
    const {
      ApiKeyAuthStrategy,
    } = require("n8n/dist/services/api-key-auth.strategy");
    apiKeyAuthStrategy = Container.get(ApiKeyAuthStrategy);
  } catch (error) {
    console.error("Error loading Api Key Auth Strategy", error);
    return;
  }
  return apiKeyAuthStrategy;
}

/**
 * https://github.com/n8n-io/n8n/blob/master/packages/cli/src/auth/auth.service.ts
 * @returns AuthService
 */
function getAuthService() {
  if (authService) return authService;
  try {
    const { AuthService } = require("n8n/dist/auth/auth.service");
    authService = Container.get(AuthService);
  } catch (error) {
    console.error("Error loading Auth Service:", error);
    return;
  }
  return authService;
}

/**
 * https://github.com/n8n-io/n8n/blob/master/packages/cli/src/workflows/workflow-validation.service.ts
 * @returns WorkflowValidateService
 */
function getWorkflowValidationService() {
  if (workflowValidationService) return workflowValidationService;
  try {
    const {
      WorkflowValidationService,
    } = require("n8n/dist/workflows/workflow-validation.service");
    workflowValidationService = Container.get(WorkflowValidationService);
  } catch (error) {
    console.error("Error loading Workflow Validation Service:", error);
    return;
  }
  return workflowValidationService;
}

/**
 * https://github.com/n8n-io/n8n/blob/master/packages/cli/src/node-types.ts
 * @returns NodeTypes
 */
function getNodeTypesService() {
  if (nodeTypesService) return nodeTypesService;
  try {
    const { NodeTypes } = require("n8n/dist/node-types");
    nodeTypesService = Container.get(NodeTypes);
  } catch (error) {
    console.error("Error loading Node Types Service:", error);
    return;
  }
  return nodeTypesService;
}

/**
 * https://github.com/n8n-io/n8n/blob/master/packages/cli/src/services/url.service.ts
 * @returns UrlService
 */
function getUrlService() {
  if (urlService) return urlService;
  try {
    const { UrlService } = require("n8n/dist/services/url.service");
    urlService = Container.get(UrlService);
  } catch (error) {
    console.error("Error loading Url Service:", error);
    return;
  }
  return urlService;
}

/**
 * @todo The license service is not yet returned correctly
 * https://github.com/n8n-io/n8n/blob/master/packages/cli/src/license.ts
 * @returns License
 */
function getLicense() {
  if (license) return license;
  try {
    const { License } = require("n8n/dist/license");
    license = Container.get(License);
  } catch (error) {
    console.error("Error loading License:", error);
    return;
  }
  return license;
}

/**
 * https://github.com/n8n-io/n8n/blob/master/packages/cli/src/modules/sso-oidc/oidc.service.ee.ts
 * @returns OidcService
 */
function getSsoOidcService() {
  if (oidcService) return oidcService;
  try {
    const {
      OidcService,
    } = require("n8n/dist/modules/sso-oidc/oidc.service.ee");
    oidcService = Container.get(OidcService);
  } catch (error) {
    console.error("Error loading SSO OIDC Service:", error);
    return;
  }
  return oidcService;
}

/**
 * https://github.com/n8n-io/n8n/blob/master/packages/cli/src/modules/sso-saml/saml.service.ee.ts
 * @returns SamlService
 */
function getSsoSamlService() {
  if (samlService) return samlService;
  try {
    const {
      SamlService,
    } = require("n8n/dist/modules/sso-saml/saml.service.ee");
    samlService = Container.get(SamlService);
  } catch (error) {
    console.error("Error loading SSO SAML Service:", error);
    return;
  }
  return samlService;
}

/**
 * https://github.com/n8n-io/n8n/blob/master/packages/%40n8n/backend-common/src/license-state.ts
 * @returns LicenseState
 */

/**
 * https://github.com/n8n-io/n8n/blob/master/packages/cli/src/services/public-api-key.service.ts
 * @returns InstanceSettings
 */
function getInstanceSettings() {
  if (instanceSettings) return instanceSettings;
  try {
    ({ InstanceSettings } = require("n8n-core"));
    instanceSettings = Container.get(InstanceSettings);
  } catch (error) {
    console.error("Error loading InstanceSettings:", error);
    return;
  }
  return instanceSettings;
}

module.exports = {
  container: {
    getOwnershipService,
    getUserService,
    getUserRepository,
    getAuthService,
    getSsoOidcService,
    getSsoSamlService,
    getInstanceSettings,
    getLicense,
    getPublicApiKeyService,
    getWorkflowValidationService,
    getNodeTypesService,
    getUrlService,
    getApiKeyAuthStrategy,
  },
};
