const { injectMiddleware } = require("../utils/router");
const { getConfig, createMiddleware } = require("./encrypt-core");

module.exports = {
  n8n: {
    ready: [
      async function ({ app }) {
        console.log("Backend Hook Loaded: encrypt-webhook-header");
        const config = getConfig();
        const mw = createMiddleware(config);
        for (const segment of [
          config.webhookPath,
          config.webhookTestPath,
          config.webhookWaitPath,
        ]) {
          console.log(`inject webhook encryption middleware /${segment}`);
          injectMiddleware(app, mw, `/${segment}`, 'rawBodyReader');
        }
      },
    ],
  },
};
