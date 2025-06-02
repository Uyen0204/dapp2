// migrations/6_deploy_warehouse_inventory.js
const RoleManagement = artifacts.require("RoleManagement");
const ItemsManagementCore = artifacts.require("ItemsManagementCore");
// ItemsPricingAndListing không cần thiết cho constructor của WarehouseInventoryManagement
const WarehouseInventoryManagement = artifacts.require("WarehouseInventoryManagement");

module.exports = async function (deployer, network, accounts) {
  const deployerAccount = accounts[0];
  const roleManagementInstance = await RoleManagement.deployed();
  const itemsManagementCoreInstance = await ItemsManagementCore.deployed();

  if (!roleManagementInstance) {
    console.error("LỖI: RoleManagement contract chưa được deploy! Không thể deploy WIM.");
    return;
  }
  if (!itemsManagementCoreInstance) {
    console.error("LỖI: ItemsManagementCore contract chưa được deploy! Không thể deploy WIM.");
    return;
  }

  console.log(`Deploying WarehouseInventoryManagement với:`);
  console.log(`  - RoleManagement tại: ${roleManagementInstance.address}`);
  console.log(`  - ItemsManagementCore tại: ${itemsManagementCoreInstance.address}`);

  await deployer.deploy(
    WarehouseInventoryManagement,
    roleManagementInstance.address,
    itemsManagementCoreInstance.address, // Constructor của WIM chỉ cần ItemsManagementCore
    { from: deployerAccount }
  );

  const wimInstance = await WarehouseInventoryManagement.deployed();
  console.log("WarehouseInventoryManagement đã được deploy tại:", wimInstance.address);
};
