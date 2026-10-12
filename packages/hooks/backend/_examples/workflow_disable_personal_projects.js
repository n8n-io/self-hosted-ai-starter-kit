/*
 Example hook to prevent creation of workflows in personal projects.
*/

module.exports = {
  workflow: {
    create: [
      async function (newWorkflow) {
        const projectId = newWorkflow.projectId;
        const personalOwner =
          await this.dbCollections.User.findPersonalOwnerForProject(projectId);
        // findPersonalOwnerForProject will return null if not a personal project
        // see: https://github.com/n8n-io/n8n/blob/master/packages/cli/src/services/hooks.service.ts
        // see: https://github.com/n8n-io/n8n/blob/master/packages/%40n8n/db/src/repositories/user.repository.ts
        if (personalOwner) {
          console.log(
            JSON.stringify({
              message: "Prevented creation of workflow in personal project",
              userId: personalOwner.id,
              projectId,
            })
          );
          // if personal owner exists, throw error to prevent creation in personal project
          throw new Error(
            "Creating workflows in personal projects is disabled"
          );
        }
      },
    ],
  },
};
