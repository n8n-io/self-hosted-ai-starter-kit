const roles = [
  "global:owner",
  "global:admin",
  "global:member",
  "global:chatUser",
];

function isValidRole(role) {
  return roles.some((r) => r === role);
}

module.exports = {
  roles,
  isValidRole,
};
