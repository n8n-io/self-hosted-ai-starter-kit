function safeStringify(value, replacer = null, space = null) {
  const seen = new WeakSet();
  return JSON.stringify(
    value,
    (key, val) => {
      if (typeof val === "object" && val !== null) {
        if (seen.has(val)) return "[Circular]";
        seen.add(val);
      }
      return replacer ? replacer(key, val) : val;
    },
    space,
  );
}

module.exports = {
  safeStringify,
};
