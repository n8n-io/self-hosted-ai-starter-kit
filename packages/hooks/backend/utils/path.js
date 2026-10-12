/**
 * Returns true if the given URL path should be treated as an HTML page request.
 *
 * A path is considered an HTML path when:
 *   - It starts with '/'
 *   - It either has no file extension (e.g. '/', '/home', '/home/page')
 *     or its extension is '.html' / '.htm'
 *
 * @param {string} urlPath - The request path (e.g. req.path or req.originalUrl)
 * @returns {boolean}
 *
 * @example
 * isHtmlPath('/')               // true
 * isHtmlPath('/index.html')     // true
 * isHtmlPath('/home')           // true
 * isHtmlPath('/home/index.html')// true
 * isHtmlPath('favicon.ico')     // false  (no leading slash)
 * isHtmlPath('/file.js')        // false
 * isHtmlPath('/image.jpg')      // false
 */
function isHtmlPath(urlPath) {
  if (typeof urlPath !== "string" || !urlPath.startsWith("/")) return false;
  // Strip query string and hash before checking the extension
  const pathname = urlPath.split("?")[0].split("#")[0];
  const lastSegment = pathname.split("/").pop();
  const dotIndex = lastSegment.lastIndexOf(".");
  if (dotIndex === -1) return true; // no extension — treat as HTML route
  const ext = lastSegment.slice(dotIndex).toLowerCase();
  return ext === ".html" || ext === ".htm";
}

module.exports = {
  isHtmlPath,
};
