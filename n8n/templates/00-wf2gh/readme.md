Template description

This workflow will backup your workflows to Github. It uses the public api to export all of the workflow data using the n8n node.

It then loops over the data checks in Github to see if a file exists that uses the workflow name. Once checked it will then update the file on Github if it exists, Create a new file if it doesn't exist and if it's the same it will ignore the file.

**Config Options**
**repo_owner** - Github owner

**repo_name** - Github repository name

**repo_path** - Path within the Github repository

<Admonition type="tip">

This workflow has been updated to use the n8n node and the code node so requires at least version 0.198.0 of n8n

</Admonition>