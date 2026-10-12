const fs = require("fs");
const path = require("path");

let cache = null;

function loadFile(filePath, { noCache = false } = {}) {
  if (!noCache && cache !== null) return cache;
  cache = fs.readFileSync(path.join(__dirname, filePath), "utf8");
  return cache;
}

module.exports = {
  loadFile,
};
