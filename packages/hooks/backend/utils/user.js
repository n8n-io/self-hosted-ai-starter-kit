const { container } = require("./di");

async function getUserById(id, includeRole = true) {
  const userRepository = container.getUserRepository();
  const users = await userRepository.findManyByIds([id], { includeRole });
  return users?.[0];
}

async function getOwner() {
  const userRepository = container.getUserRepository();
  const owner = await userRepository.findOne({
    where: { role: { slug: "global:owner" } },
    relations: ["role"],
  });
  return owner;
}

module.exports = {
  getUserById,
  getOwner
};
