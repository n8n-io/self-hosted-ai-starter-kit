const { injectMiddleware } = require("./utils/router");

module.exports = {
  n8n: {
    ready: [
      async function ({ app }, config) {
              
        // intercept node.json response to modify chatTrigger node
        injectMiddleware(app, async (req, res, next) => {
            const path = String(req.originalUrl);
            const method = req.method;
            
            if (path === "/types/nodes.json" && method === "GET") {
              console.log("reached /types/nodes.json, intercepting response to modify node.json");

              const originalWrite = res.write;

              res.write = function (chunk, encoding, callback) {
                if (chunk) {
                  let body = chunk.toString("utf8");
                  if (body.includes("Make Chat Publicly Available")) {
                    console.log("found the defaults substring");
                    //the body replace is very hacky but I didnt want to parse it to JSON to avoid any issues with formatting. We should check for a more elegant solution. 
                    body = body.replace("manual chat interface\"", "manual chat interface\",\"displayOptions\":{\"show\":{\"public\":[true]}}");
                    chunk = Buffer.from(body, encoding);
                    return originalWrite.call(this, chunk, encoding, callback);
                  }
                }
                return originalWrite.call(this, chunk, encoding, callback);
              };
            }
            next();
          },
          "/types/nodes.json",
        );
      },
    ],
  },
};
