const { container } = require("../utils/di");

const getSsoSetting = async (_req, res) => {
  const oidcService = container.getSsoOidcService();
  const samlService = container.getSsoSamlService();
  const oidc = await oidcService.getRedactedConfig();
  const saml = samlService.samlPreferences;
  res.json({ oidc, saml });
};

const createSsoOIDCSetting = async (req, res) => {
  const oidcService = container.getSsoOidcService();
  await oidcService.updateConfig(req.body);
  const config = oidcService.getRedactedConfig();
  res.json(config);
};

const createSsoSamlSetting = async (req, res) => {
  const samlService = container.getSsoSamlService();
  const result = await samlService.setSamlPreferences(req.body);
  res.json(result);
};

module.exports = {
  getSsoSetting,
  createSsoOIDCSetting,
  createSsoSamlSetting,
};
