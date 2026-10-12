"use strict";

/**
 * Wraps an Express response object to intercept HTML responses and inject
 * a script tag before </head> (falling back to </body>, then end of document).
 *
 * Usage:
 *   const { injectScriptIntoHtml } = require("../utils/stream");
 *
 *   app.use((req, res, next) => {
 *     injectScriptIntoHtml(res, '<script src="/my-script.js"></script>');
 *     next();
 *   });
 *
 * @param {import("express").Response} res       - Express response object
 * @param {string}                     scriptTag - Raw HTML string to inject (e.g. a <script> tag)
 */
function injectScriptIntoHtml(res, scriptTag) {
  const originalWrite = res.write.bind(res);
  const originalEnd = res.end.bind(res);

  const chunks = [];
  let isHtml = null; // resolved lazily once Content-Type is known

  function isHtmlResponse() {
    if (isHtml !== null) return isHtml;
    const contentType = res.getHeader("content-type") || "";
    isHtml = contentType.includes("text/html");
    return isHtml;
  }

  function injectIntoBuffer(html) {
    // Prefer injecting before </head>, then </body>, then append to end
    const targets = ["</head>", "</body>"];
    for (const target of targets) {
      const idx = html.lastIndexOf(target);
      if (idx !== -1) {
        return html.slice(0, idx) + scriptTag + "\n" + html.slice(idx);
      }
    }
    return html + scriptTag;
  }

  res.write = function (chunk, encoding, callback) {
    if (!isHtmlResponse()) {
      return originalWrite(chunk, encoding, callback);
    }
    // Buffer the chunk — injection happens in end() once the full body is available
    chunks.push(
      Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, encoding || "utf8"),
    );
    if (typeof encoding === "function")
      encoding(); // encoding used as callback
    else if (typeof callback === "function") callback();
    return true;
  };

  res.end = function (chunk, encoding, callback) {
    if (!isHtmlResponse()) {
      return originalEnd(chunk, encoding, callback);
    }

    if (chunk) {
      chunks.push(
        Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, encoding || "utf8"),
      );
    }

    const body = Buffer.concat(chunks).toString("utf8");
    const injected = injectIntoBuffer(body);
    const injectedBuffer = Buffer.from(injected, "utf8");

    // Update Content-Length if it was set, since the body size changed
    if (res.getHeader("content-length")) {
      res.setHeader("content-length", injectedBuffer.byteLength);
    }

    return originalEnd(
      injectedBuffer,
      typeof encoding !== "function" ? encoding : undefined,
      typeof encoding === "function" ? encoding : callback,
    );
  };
}

module.exports = {
  injectScriptIntoHtml
};
