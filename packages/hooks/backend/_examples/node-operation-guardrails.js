function getAllNodesEnabled(workflowData) {
  // ignore empty workflow
  if (!workflowData.nodes.length) {
    return [];
  }
  // get all required enabled nodes
  const nodes = workflowData.nodes.filter((n) => !n.disabled);
  return nodes;
}

function throwNodesError(message) {
  throw new Error(`Node error: ${message}`);
}

function verifyHttpNode(node) {
  if (!node.parameters) return true;
  const authentication = node.parameters.authentication;
  if (!authentication) return true;
  if (authentication === "predefinedCredentialType") {
    throwNodesError("Use of http node predefined credentials forbidden.");
  }
}

function verifyWorkflowNodes(workflowData) {
  const nodes = getAllNodesEnabled(workflowData);
  console.log("nodes", nodes);
  if (!nodes.length) return true;
  nodes.forEach((node) => {
    if (node.type === "n8n-nodes-base.httpRequest") {
      verifyHttpNode(node);
    }
  });
}

module.exports = {
  workflow: {
    update: [
      async function (workflowData) {
        verifyWorkflowNodes(workflowData);
      },
    ],
    preExecute: [
      async function (workflowData) {
        verifyWorkflowNodes(workflowData);
      },
    ],
  },
};
