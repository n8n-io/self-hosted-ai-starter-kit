const { container } = require("../utils/di");
const { getUserById } = require("../utils/user");

const createJwtToken = async (req, res) => {
  const authService = container.getAuthService();
  const { id } = req.params;
  const user = await getUserById(id);
  if (!user) {
    return res.status(400).json({ error: "User does not exist" });
  }
  const jwt = authService.issueJWT(user);
  res.json({ jwt });
};

module.exports = {
  createJwtToken,
};
