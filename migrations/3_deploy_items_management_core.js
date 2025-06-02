// migrations/3_deploy_items_management_core.js
const RoleManagement = artifacts.require("RoleManagement");
const ItemsManagementCore = artifacts.require("ItemsManagementCore");

module.exports = async function (deployer, network, accounts) {
  const roleManagementInstance = await RoleManagement.deployed();
  if (!roleManagementInstance) {
    console.error("LỖI: RoleManagement contract chưa được deploy hoặc deploy thất bại!");
    return;
  }

  console.log("Deploying ItemsManagementCore với RoleManagement tại:", roleManagementInstance.address);
  await deployer.deploy(ItemsManagementCore, roleManagementInstance.address);

  const itemsManagementCoreInstance = await ItemsManagementCore.deployed();
  console.log("ItemsManagementCore đã được deploy tại:", itemsManagementCoreInstance.address);
};
