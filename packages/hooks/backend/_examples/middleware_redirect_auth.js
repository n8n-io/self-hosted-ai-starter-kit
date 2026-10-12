const Layer = require("router/lib/layer");

module.exports = {
  n8n: {
    ready: [
      async function ({ app }, config) {
        // create express middleware layer
        const layer = new Layer(
          "/",
          {
            strict: false,
            end: false,
          },
          async (req, res, next) => {
            console.log("Hello from backend hook middleware");
            if (!req.cookies?.["n8n-auth"]) {
              res.redirect("https://n8n.io");
            } else {
              next();
            }
          }
        );
        // add layer after cookie parser so n8n-auth cookie is available
        const { stack } = app.router;
        const index = stack.findIndex((l) => l.name === "cookieParser");
        stack.splice(index + 1, 0, layer);
      },
    ],
  },
};
