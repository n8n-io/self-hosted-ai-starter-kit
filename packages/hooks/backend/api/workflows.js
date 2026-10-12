const { container } = require("../utils/di");

const validateWorkflow = async (req, res) => {
  const workflowValidation = container.getWorkflowValidationService();
  const nodeTypes = container.getNodeTypesService();
  const { workflow } = req.body;
  if (!workflow) {
    return res.status(400).json({
      error: "Invalid body. Requires: { workflow: {} } ",
    });
  }
  const { nodes, connections } = workflow;
  if (!nodes || !connections) {
    return res.status(400).json({
      error: "Invalid workflow. Requires: { nodes: {}, connections: {} } ",
    });
  }
  const validation = workflowValidation.validateForActivation(
    nodes,
    connections,
    nodeTypes,
  );
  res.json(validation);
};

module.exports = {
  validateWorkflow,
};
