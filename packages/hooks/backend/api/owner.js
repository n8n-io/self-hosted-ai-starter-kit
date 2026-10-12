const { container } = require("../utils/di");
const { getFutureUnixTimestamp } = require("../utils/date");
const { getApiKeyScopesForRole } = require("../utils/scopes");

/**
 * Setup owner with body payload email, firstName, lastName, password.
 * controller: https://github.com/n8n-io/n8n/blob/0e1ef918f40b4350fd0207c5da3e20afd9ab2cc9/packages/cli/src/controllers/owner.controller.ts#L25
 * service: https://github.com/n8n-io/n8n/blob/0e1ef918f40b4350fd0207c5da3e20afd9ab2cc9/packages/cli/src/services/ownership.service.ts#L224
 */
const setupOwner = async (req, res) => {
  const ownershipService = container.getOwnershipService();
  const userService = container.getUserService();
  const publicApiKeyService = container.getPublicApiKeyService();
  const { getApiKeyScopesForRole } = require("../utils/scopes");
  // create owner
  let owner = await ownershipService.setupOwner(req.body);
  // create api key
  const label = "master api key";
  const expiresAt = getFutureUnixTimestamp(365 * 99);
  const scopes = getApiKeyScopesForRole(owner);
  const { apiKey } = await publicApiKeyService.createPublicApiKeyForUser(
    owner,
    {
      label,
      expiresAt,
      scopes,
    },
  );
  // to public owner object
  owner = await userService.toPublic(owner, { withScopes: false });
  res.json({ owner, apiKey });
};

const getOwner = async (_req, res) => {
  const ownershipService = container.getOwnershipService();
  const userService = container.getUserService();
  const owner = await ownershipService.getInstanceOwner();
  // todo: fix toPublic error missing role.slug
  //const ownerPublic = await userService.toPublic(owner, { withScopes: true });
  res.json(owner);
};

module.exports = {
  setupOwner,
  getOwner,
};
