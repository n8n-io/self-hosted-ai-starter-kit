const { container } = require("../utils/di");
const validator = require("validator");
const { getUserById } = require("../utils/user");
const { getApiKeyScopesForRole } = require("../utils/scopes");

const listApiKeys = async (req, res) => {
  const publicApiKeyService = container.getPublicApiKeyService();
  const { id } = req.params;
  if (!validator.isUUID(id)) {
    return res.status(400).json({ error: "not a valid uuid" });
  }
  const apiKeys = await publicApiKeyService.getRedactedApiKeysForUser({ id });
  res.json({ data: apiKeys });
};

const createApiKey = async (req, res) => {
  const publicApiKeyService = container.getPublicApiKeyService();
  const { id } = req.params;
  const { label, expiresAt } = req.body;
  let { scopes } = req.body;
  if (!validator.isUUID(id)) {
    return res.status(400).json({ error: "not a valid uuid" });
  }
  if (!label || !expiresAt) {
    return res.status(400).json({
      error: "Invalid body. Requires: { label, expiresAt, scopes? } ",
    });
  }
  const user = await getUserById(id);
  if (!user) {
    return res.status(400).json({ error: "User does not exist" });
  }
  scopes = scopes || getApiKeyScopesForRole(user);
  const apiKey = await publicApiKeyService.createPublicApiKeyForUser(user, {
    label,
    expiresAt,
    scopes,
  });
  res.json(apiKey);
};

module.exports = {
  listApiKeys,
  createApiKey
};
