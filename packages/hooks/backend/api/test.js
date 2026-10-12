const testPublic = (req, res) => {
  res.json({ success: true, message: "Test Public completed" });
};

const testAuthenticated = (req, res) => {
  res.json({ success: true, message: "Test Authenticated completed" });
};

module.exports = {
  testPublic,
  testAuthenticated,
};
