module.exports = {
  n8n: {
    ready: [
      async function ({ app }, config) {
        console.log("Backend Hook Loaded: Workflow Update hook");
      },
    ],
  },
  workflow: {
    update: [
      async function (workflowData) {
        console.log(`[${new Date().toLocaleString()}] On Workflow Update:`, workflowData.name);
      },
    ],
  },
};
