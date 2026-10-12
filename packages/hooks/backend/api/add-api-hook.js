const { createApiRouter } = require("./router");
const { injectApiRouter } = require("../utils/router");
module.exports = {
  n8n: {
    ready: [
      async function ({ app }) {
        console.log("Backend Hook Loaded: Custom API Router (/api-custom/v1)");
        injectApiRouter(app, "/api-custom/v1", createApiRouter());
      },
    ],
  },
};
