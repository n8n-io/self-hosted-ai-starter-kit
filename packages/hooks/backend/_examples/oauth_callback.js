/*
Change redirectUri for OAuth2 authentication
*/
const OAUTH_BASE_URL = "https://n8n.example.com"

const oauthCallbackUrls = Object.freeze({
  oauth1: OAUTH_BASE_URL + '/oauth1/callback',
  oauth2: OAUTH_BASE_URL + '/oauth2/callback',
});

module.exports = {
  frontend: {
    settings: [
      async function (settings) {
        // Prevent n8n from overwriting these urls
        Object.defineProperty(settings, 'oauthCallbackUrls', {
          get: () => oauthCallbackUrls,
          set: () => {},
        });
        console.log("frontend:settings", settings);
      },
    ],
  },
  oauth2: {
    authenticate: [
      async function (options) {
        options.redirectUri = OAUTH_BASE_URL + '/oauth2/callback';
        console.log("oauth2:authenticate", options);
      },
    ],
    callback: [
      async function (options) {
        options.redirectUri = OAUTH_BASE_URL + '/oauth2/callback';
        console.log("oauth2:callback", options);
      },
    ],
  },
};
