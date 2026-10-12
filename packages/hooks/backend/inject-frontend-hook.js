const { injectMiddleware } = require("./utils/router");
const { injectScriptIntoHtml } = require("./utils/stream");
const { loadFile } = require("./utils/file");
const { isHtmlPath } = require("./utils/path");

function isHtmlRoute(path, method) {
  // ignore routes that don't serve html files
  const ignored = ["assets", "static", "rest", "api", "types"];
  const prefixes = ignored.map((p) => "/" + p);
  const isIgnored = (url) => prefixes.some((p) => url.startsWith(p));
  return !isIgnored(path) && method === "GET" && isHtmlPath(path);
}

module.exports = {
  n8n: {
    ready: [
      async function ({ app }, config) {
        console.log("Backend Hook Loaded: Inject Frontend hook");

        // serve frontend-hook.js
        app.get("/rest/frontend-hook.js", (_req, res) => {
          res.set("content-type", "text/javascript");
          res.send(loadFile("../../frontend/hooks.js"));
        });

        const scriptTag = '<script src="/rest/frontend-hook.js"></script>';
        // inject html script tag middleware
        injectMiddleware(
          app,
          async (req, res, next) => {
            const path = String(req.originalUrl);
            const method = req.method;
            if (isHtmlRoute(path, method)) {
              injectScriptIntoHtml(res, scriptTag);
            }
            next();
          },
          "/",
        );
      },
    ],
  },
};
