/*
 Limit the number of workflows that can be activated
*/
const WORKFLOW_LIMIT = 1;

module.exports = {
  workflow: {
    activate: [
      async function (workflowData) {
        console.log("workflow activate", { workflowData });

        const activeWorkflows = await this.dbCollections.Workflow.count({
          active: true,
        });

        if (activeWorkflows > WORKFLOW_LIMIT) {
          throw new Error(
            `Active workflow limit of ${WORKFLOW_LIMIT} reached.`
          );
        }
      },
    ],
  },
};
