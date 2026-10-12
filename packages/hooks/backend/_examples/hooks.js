/*
 Log some hook events
*/

module.exports = {
  n8n: {
    ready: [
      async function ({ app }, config) {
        console.log("ready", { app, config });
      },
    ],
  },
  credentials: {
    create: [
      async function (...args) {
        // generic way to log all params
        console.log("credentials create test params", { ...args });
        console.log("credentials create test params deep", JSON.stringify({ ...args }, null, 2));
      },
      async function (credentialData, credentialType) {
        console.log("credentials create", { credentialData, credentialType });
      },
    ],
    update: [
      async function (credentialData, credentialType) {
        console.log("credentials update", { credentialData, credentialType });
      }
    ],
    delete: [
      async function (credentialData, credentialType) {
        console.log("credentials delete", { credentialData, credentialType });
      }
    ],  
  },
  workflow: {
    preExecute: [
      async function (workflowData, executionMode) {
        console.log("workflow preExecute", { workflowData, executionMode });
      },
    ],
    postExecute: [
      async function (executionData, workflowData, executionId) {
        console.log("workflow postExecute", {
          executionData,
          workflowData,
          executionId,
        });
      },
    ],
  },
};
