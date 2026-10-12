const { injectMiddleware } = require("../utils/router");
const {
  getConfig,
  createMiddleware,
  isMcpExecuteWorkflowCall,
} = require("./encrypt-core");

module.exports = {
  n8n: {
    ready: [
      async function ({ app }) {
        console.log("Backend Hook Loaded: encrypt-mcp-execute-workflow-header");
        const config = getConfig();
        const mw = createMiddleware(config, (req) =>
          isMcpExecuteWorkflowCall(req.body),
        );
        for (const segment of [
          config.mcpPath,
          config.mcpTestPath,
          config.mcpInstancePath,
        ]) {
          console.log(`inject mcp encryption middleware /${segment}`);
          injectMiddleware(app, mw, `/${segment}`);
        }
      },
    ],
  },
};
