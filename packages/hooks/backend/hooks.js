const { mergeHooks } = require("./utils/merge");
const injectFrontendHooks = require("./inject-frontend-hook");
const editNodesJsonHook = require("./edit-nodes-json-hook");
const addApiRouterHooks = require("./api/add-api-hook");
const onWorkflowUpdate = require("./workflow-update-hook");
const embedLoginHook = require("./embed-login-hook");
const encryptWebhookHeader = require("./middleware/encrypt-webhook-header");
const encryptMcpExecuteWorkflowHeader = require("./middleware/encrypt-mcp-execute-workflow-header");
const workflowNodeParameterGuardrail = require("./_examples/workflow_node_parameter_guardrail")

module.exports = mergeHooks([
  addApiRouterHooks,
  injectFrontendHooks,
  editNodesJsonHook,
  onWorkflowUpdate,
  embedLoginHook,
  // encryptWebhookHeader,
  // encryptMcpExecuteWorkflowHeader,
  workflowNodeParameterGuardrail
]);
