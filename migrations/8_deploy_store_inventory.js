// migrations/8_deploy_store_inventory.js
const RoleManagement = artifacts.require("RoleManagement");
const ItemsManagementCore = artifacts.require("ItemsManagementCore");
// ItemsPricingAndListing không cần thiết cho constructor của StoreInventoryManagement
const StoreInventoryManagement = artifacts.require("StoreInventoryManagement");

module.exports = async function (deployer, network, accounts) {
  const deployerAccount = accounts[0];
  const roleManagementInstance = await RoleManagement.deployed();
  const itemsManagementCoreInstance = await ItemsManagementCore.deployed();

  if (!roleManagementInstance) {
    console.error("LỖI: RoleManagement contract chưa được deploy! Không thể deploy StoreInventoryManagement.");
    return;
  }
  if (!itemsManagementCoreInstance) {
    console.error("LỖI: ItemsManagementCore contract chưa được deploy! Không thể deploy StoreInventoryManagement.");
    return;
  }

  console.log(`Deploying StoreInventoryManagement với:`);
  console.log(`  - RoleManagement tại: ${roleManagementInstance.address}`);
  console.log(`  - ItemsManagementCore tại: ${itemsManagementCoreInstance.address}`);

  await deployer.deploy(
    StoreInventoryManagement,
    roleManagementInstance.address,
    itemsManagementCoreInstance.address, // Constructor của SIM chỉ cần ItemsManagementCore
    { from: deployerAccount }
  );

  const simInstance = await StoreInventoryManagement.deployed();
  console.log("StoreInventoryManagement đã được deploy tại:", simInstance.address);
};
