/**
 * A hook that disables the user management and uses owner for all requests
 */
const { dirname, resolve } = require("path");
const Layer = require("express/lib/router/layer");

const n8nDir = dirname(require.resolve("n8n"));
const jwtAuth = require(resolve(n8nDir, "auth/jwt"));

async function disableUmHook({ app }, config) {
  await this.dbCollections.Settings.update(
    { key: "userManagement.isInstanceOwnerSetUp" },
    { value: JSON.stringify(true) }
  );

  config.set("userManagement.isInstanceOwnerSetUp", true);

  const owner = await this.dbCollections.User.findOne({
    where: { role: "global:owner" },
  });

  owner.email = "demo@n8n.io";
  owner.firstName = "Demo";
  owner.lastName = "McDemoFace";

  await this.dbCollections.User.save(owner);

  jwtAuth.resolveJwt = () => owner;

  const { stack } = app._router;
  const index = stack.findIndex((l) => l.name === "cookieParser");
  stack.splice(
    index + 4,
    3,
    new Layer(
      "/",
      {
        strict: false,
        end: false,
      },
      async (req, res, next) => {
        req.user = owner;
        req.cookies = { "n8n-auth": "fake" };
        next();
      }
    )
  );
}

module.exports = {
  n8n: {
    ready: [disableUmHook],
  },
};
