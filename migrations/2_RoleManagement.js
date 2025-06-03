// migrations/2_RoleManagement.js
const RoleManagement = artifacts.require("RoleManagement");

module.exports = function (deployer) {
  deployer.deploy(RoleManagement);
};
