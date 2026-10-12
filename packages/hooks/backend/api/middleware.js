const { error } = require("node:console");
const { container } = require("../utils/di");

/**
 * Authentication middleware for n8n owner account public api keys.
 */
const createAuthMiddleware = () => {
  const apiKeyAuthStrategy = container.getApiKeyAuthStrategy();
  const headerKey = "x-n8n-api-key";

  const middleware = async (req, res, next) => {
    let isValid = true;
    if (!req.headers[headerKey]) {
      isValid = false;
    } else {
      isValid = await apiKeyAuthStrategy(req);
    }
    if (isValid && !req.user.role.slug === "global:owner") {
      isValid = false;
    }
    if (!isValid) {
      return res.status(401).json({ error: "Unauthorized" });
    }
    next();
  };
  return middleware;
};

function createErrorMiddleware() {
  // Express identifies error-handling middleware by its 4-argument signature
  const middleware = (err, req, res, _next) => {
    const { originalUrl, method } = req;
    const status = err.status ?? err.statusCode ?? 500;
    const message = err.message ?? "Internal Server Error";
    console.error(`Error ${method} ${originalUrl} ${status}`, err.stack);
    res.status(status).json({ error: message });
  };
  return middleware;
}

module.exports = {
  createAuthMiddleware,
  createErrorMiddleware,
};
