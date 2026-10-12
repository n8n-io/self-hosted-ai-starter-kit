const { encrypt } = require("../utils/crypto");

function getConfig() {
  const encryptionKey = process.env.ENCRYPTION_KEY;
  const headerName = process.env.ENCRYPTED_HEADER_NAME;
  if (!encryptionKey) throw new Error("ENCRYPTION_KEY env var is required");
  if (!headerName) throw new Error("ENCRYPTED_HEADER_NAME env var is required");
  return {
    encryptionKey,
    headerName: headerName.toLowerCase(),
    webhookPath: process.env.N8N_ENDPOINT_WEBHOOK ?? "webhook",
    webhookTestPath: process.env.N8N_ENDPOINT_WEBHOOK_TEST ?? "webhook-test",
    webhookWaitPath: process.env.N8N_ENDPOINT_WEBHOOK_WAIT ?? "webhook-waiting",
    mcpPath: process.env.N8N_ENDPOINT_MCP ?? "mcp",
    mcpTestPath: process.env.N8N_ENDPOINT_MCP_TEST ?? "mcp-test",
    mcpInstancePath: "mcp-server/http",
  };
}

function encryptHeaderInPlace(req, { encryptionKey, headerName }) {
  let value = req.headers[headerName];
  if (typeof value === "string" && value.length > 0) {
    req.headers[headerName] = encrypt(value, encryptionKey);
    return;
  }
  value =
    req.body?.params?.arguments?.inputs?.webhookData?.headers?.[headerName];
  if (typeof value === "string" && value.length > 0) {
    req.body.params.arguments.inputs.webhookData.headers[headerName] = encrypt(
      value,
      encryptionKey,
    );
  }
}

function createMiddleware(config, shouldRun = () => true) {
  return (req, _res, next) => {
    try {
      if (shouldRun(req)) encryptHeaderInPlace(req, config);
    } catch (err) {
      console.error("encrypt-core middleware error", err);
    }
    next();
  };
}

function isMcpExecuteWorkflowCall(body) {
  return (
    body?.method === "tools/call" && body?.params?.name === "execute_workflow"
  );
}

module.exports = { getConfig, createMiddleware, isMcpExecuteWorkflowCall };
