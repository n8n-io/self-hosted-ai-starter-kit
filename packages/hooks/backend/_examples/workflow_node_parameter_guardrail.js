/*
 Limit the number of workflows that can be activated
*/
const WORKFLOW_LIMIT = 1;

module.exports = {
  workflow: {
    /*
    // Disabled for testing. Enable for production. 
    update: [
      async function (workflowData) {
        // will error on every workflow update (auto save)
        await onWorkflowChange(workflowData);
      },
    ], 
    */ 
    activate: [
      async function (workflowData) {
        // will error on workflow activate
        await onWorkflowChange(workflowData);
      },
    ],
  },
};

/**
 * Main hook function called when a workflow is activated.
 * @param {Object} workflowData - The full n8n workflow JSON object.
 */
async function onWorkflowChange(workflowData) {
  try {
    // Extract nodes from the workflow data.
    // We check workflowData.nodes to validate the root level definition.
    const nodes = workflowData?.nodes || [];

    if (nodes.length > 0) {
      validateWorkflowNodes(nodes);
    }

    console.log(
      `Workflow "${workflowData.name}" passed all guardrail checks. Proceeding with activation...`,
    );
    // Add your actual activation logic here
  } catch (error) {
    // Log the error and bubble it up to prevent the workflow from activating
    console.error(`Workflow Activation Failed: ${error.message}`);
    throw error;
  }
}

/**
 * Iterates through all nodes and triggers the guardrail checks.
 * @param {Array} nodes - Array of n8n node objects.
 */
function validateWorkflowNodes(nodes) {
  nodes.forEach((node) => {
    const nodeType = node.type;
    applyGuardrails(node, nodeType);
  });
}

/**
 * Switchboard function to route the node to its specific guardrail rules based on nodeType.
 * @param {Object} node - The individual n8n node object.
 * @param {String} nodeType - The extracted type of the node.
 */
function applyGuardrails(node, nodeType) {
  switch (nodeType) {
    case "n8n-nodes-base.microsoftOutlook":
      validateOutlookNode(node);
      break;
    case "n8n-nodes-base.httpRequest":
      validateHttpRequestNode(node);
      break;
    // Add additional node types and guardrail functions here as needed
    default:
      break;
  }
}

/**
 * GUARDRAIL 1: Outlook nodes must only send emails to @n8n.io domains.
 */
function validateOutlookNode(node) {
  const recipients = node.parameters?.toRecipients;

  if (!recipients) return; // Skip if no recipients are defined

  // Split by comma in case there are multiple recipients, and trim whitespace
  const emailList = recipients.split(",").map((email) => email.trim());

  for (const email of emailList) {
    // Check if the email ends with the allowed domain
    // Note: This specifically evaluates static text. If users use n8n expressions (e.g., {{$json.email}}),
    // static code analysis cannot resolve it prior to execution.
    if (!email.endsWith("@n8n.io")) {
      throw new Error(
        `Guardrail Violation in node "${node.name}": Outlook recipients are restricted to @n8n.io domains. Found unauthorized recipient: ${email}`,
      );
    }
  }
}

/**
 * GUARDRAIL 2: HTTP Request nodes cannot use microsoftOutlookOAuth2Api credentials.
 */
function validateHttpRequestNode(node) {
  // Check both the parameters definition and the attached credentials object
  const credentialTypeParam = node.parameters?.nodeCredentialType;
  const attachedCredentials = node.credentials;

  const usesOutlookOAuthViaParam =
    credentialTypeParam === "microsoftOutlookOAuth2Api";
  const usesOutlookOAuthViaObject =
    attachedCredentials && attachedCredentials["microsoftOutlookOAuth2Api"];

  if (usesOutlookOAuthViaParam || usesOutlookOAuthViaObject) {
    throw new Error(
      `Guardrail Violation in node "${node.name}": HTTP Request nodes are not permitted to use "microsoftOutlookOAuth2Api" credentials.`,
    );
  }
}
