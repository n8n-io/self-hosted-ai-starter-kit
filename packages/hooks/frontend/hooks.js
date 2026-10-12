console.log("Frontend hook loaded");

window.n8nExternalHooks = {
  app: {
    mount: [
      function (store, meta) {
        console.log("Frontend hook: app.mount");
      },
    ],
  },
};
