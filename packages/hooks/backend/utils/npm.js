const { execSync } = require("child_process");

/**
 * Returns the install path of an npm package by name.
 * Checks global install first, then falls back to local.
 * Returns null if the package is not found in either.
 *
 * @param {string} packageName
 * @returns {string | null}
 */
function getPackageInstallPath(packageName) {
  for (const args of ["list -g", "list"]) {
    try {
      const command = `npm ${args} --parseable --depth=0 ${packageName}`;
      console.log("n8n command", command);
      const result = execSync(command, {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }).trim();
      console.log("n8n install path", result);
      if (result) return result;
    } catch {
      // not found in this scope, try next
    }
  }
  console.error("N8n install path not found");
  return null;
}

const n8nInstallPath = getPackageInstallPath("n8n");

module.exports = { n8nInstallPath };
