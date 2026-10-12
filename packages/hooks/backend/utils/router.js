const Layer = require("router/lib/layer");

function injectMiddleware(app, middleware, path = "/", after = "cookieParser") {
  // create express middleware layer
  const layer = new Layer(
    path,
    {
      strict: false,
      end: false,
    },
    middleware,
  );
  // add layer after cookie parser so n8n-auth cookie is available
  const { stack } = app.router;
  // console.log(stack.filter(l => l.name).map(l => ({ name: l.name })));
  const index = stack.findIndex((l) => l.name === after);
  stack.splice(index + 1, 0, layer);
}

function injectApiRouter(app, path, router) {
  app.use(path, router);
  const { stack } = app.router;
  const index = stack.findIndex((l) => l.name === "cookieParser");
  stack.splice(index + 1, 0, stack.pop());
}

module.exports = {
  injectMiddleware,
  injectApiRouter,
};
