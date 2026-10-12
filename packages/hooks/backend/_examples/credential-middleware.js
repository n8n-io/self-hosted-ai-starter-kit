const { injectMiddleware } = require("utils/router");

function onCredentialCreateOrUpdated(credential, res) {
  const { type, data } = credential;
  // jenkins server api
  if (type === "jenkinsApi") {
    const { baseUrl } = data;
    if (!baseUrl.toLowerCase().includes("bcg")) {
      res.status(400).json({
        message: `jenkinsApi credentials baseUrl does not contain 'bcg': ${baseUrl}`,
      });
      return false;
    }
  }
  return true;
}

module.exports = {
  n8n: {
    ready: [
      async function ({ app }, config) {
        console.log('Backend Hook Loaded');
        // inject custom middleware to intercept /rest/credentials
        // create credentials:
        // https://github.com/n8n-io/n8n/blob/31f422b374a7cdec01a99e7a59044f969de25cd2/packages/cli/src/credentials/credentials.controller.ts#L175
        // update credentials:
        // https://github.com/n8n-io/n8n/blob/31f422b374a7cdec01a99e7a59044f969de25cd2/packages/cli/src/credentials/credentials.controller.ts#L204
        injectMiddleware(
          app,
          async (req, res, next) => {
            let success = true;
            if (req.originalUrl === "/rest/credentials/test") {
              // ignore test requests
            } else if (req.method === "POST") {
              console.log(`POST: /rest/credentials`, req.body);
              success = onCredentialCreateOrUpdated(req.body, res);
            } else if (req.method === "PATCH") {
              console.log(`PATCH: /rest/credentials`, req.body);
              success = onCredentialCreateOrUpdated(req.body, res);
            }
            if (success) next();
          },
          "/rest/credentials"
        );
      },
    ],
  },
};
