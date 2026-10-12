/**
 * Merges a list of n8n backend hook objects into a single hooks object.
 * Each hook object has 2-level nested fields containing arrays of async functions.
 * Functions from all hooks are concatenated in order for each category/event.
 *
 * @param {...Object} hooksList - Hook objects to merge
 * @returns {Object} Merged hooks object
 */
function mergeHooks(hooksList) {
    const merged = {};

    for (const hooks of hooksList) {
        for (const category of Object.keys(hooks)) {
            if (!merged[category]) {
                merged[category] = {};
            }
            for (const event of Object.keys(hooks[category])) {
                if (!merged[category][event]) {
                    merged[category][event] = [];
                }
                merged[category][event].push(...hooks[category][event]);
            }
        }
    }

    return merged;
}

module.exports = { mergeHooks };
