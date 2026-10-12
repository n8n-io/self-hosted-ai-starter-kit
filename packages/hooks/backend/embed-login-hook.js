const { container } = require("./utils/di");
const { getOwner } = require("./utils/user");

loginEmbed = async (req, res) => {
  const authService = container.getAuthService();
  res.json({ success: true });
};

module.exports = {
  n8n: {
    ready: [
      async function ({ app }, config) {
        console.log("Backend Hook Loaded: Embed Login hook");

        app.get("/rest/embed/login", async (req, res) => {
          const authService = container.getAuthService();
          const urlService = container.getUrlService();
          const user = await getOwner();
          authService.issueCookie(res, user, true, req.browserId);
          res.redirect(urlService.getInstanceBaseUrl() + "/");
        });
      },
    ],
  },
};
