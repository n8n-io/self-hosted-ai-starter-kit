const Sentry = require("@sentry/node");

// Initialize sentry client and send custom metrics
// https://docs.sentry.io/platforms/javascript/guides/node/
/**
Sentry.init({
  dsn: '__DSN__',
  // ...
});
 */

module.exports = {
  n8n: {
    ready: [
      async function ({ app }, config) {
        console.log("ready", { app, config });
      },
    ],
  },
  workflow: {
    postExecute: [
      async function (executionData, workflowData, executionId) {
        // get required execution data
        const { id, name } = workflowData;
        const { mode, finished } = executionData;
        const { resultData } = executionData.data;
        const runData = resultData.runData;
        
        // example to count items for each executed node
        const customRunData = {};
        const runNodeKeys = Object.keys(runData);
        runNodeKeys.forEach(key => {
          const nodeRunData = runData[key];
          const items = nodeRunData[0].data.main[0];
          customRunData[key] = items.length;
        });
        
        // log required execution data including custom run data with node item counts
        console.log("workflow postExecute", {
          id,
          name,
          executionId,
          mode,
          finished,
          customRunData: customRunData,
        });
      },
    ],
  },
};
