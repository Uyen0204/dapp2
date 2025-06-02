// migrations/7_deploy_warehouse_supplier_order.js
const RoleManagement = artifacts.require("RoleManagement");
const ItemsManagementCore = artifacts.require("ItemsManagementCore");
const ItemsPricingAndListing = artifacts.require("ItemsPricingAndListing"); // WSOM cần cả hai
const CompanyTreasuryManager = artifacts.require("CompanyTreasuryManager");
const WarehouseSupplierOrderManagement = artifacts.require("WarehouseSupplierOrderManagement");

module.exports = async function (deployer, network, accounts) {
  const roleManagementInstance = await RoleManagement.deployed();
  const itemsManagementCoreInstance = await ItemsManagementCore.deployed();
  const itemsPricingAndListingInstance = await ItemsPricingAndListing.deployed();
  const companyTreasuryManagerInstance = await CompanyTreasuryManager.deployed();

  if (!roleManagementInstance) {
    console.error("LỖI: RoleManagement contract chưa được deploy! Không thể deploy WSOM.");
    return;
  }
  if (!itemsManagementCoreInstance) {
    console.error("LỖI: ItemsManagementCore contract chưa được deploy! Không thể deploy WSOM.");
    return;
  }
  if (!itemsPricingAndListingInstance) {
    console.error("LỖI: ItemsPricingAndListing contract chưa được deploy! Không thể deploy WSOM.");
    return;
  }
  if (!companyTreasuryManagerInstance) {
    console.error("LỖI: CompanyTreasuryManager contract chưa được deploy! Không thể deploy WSOM.");
    return;
  }

  console.log(`Deploying WarehouseSupplierOrderManagement với:`);
  console.log(`  - RoleManagement tại: ${roleManagementInstance.address}`);
  console.log(`  - ItemsManagementCore tại: ${itemsManagementCoreInstance.address}`);
  console.log(`  - ItemsPricingAndListing tại: ${itemsPricingAndListingInstance.address}`);
  console.log(`  - CompanyTreasuryManager tại: ${companyTreasuryManagerInstance.address}`);

  await deployer.deploy(
    WarehouseSupplierOrderManagement,
    roleManagementInstance.address,
    itemsManagementCoreInstance.address,
    itemsPricingAndListingInstance.address,
    companyTreasuryManagerInstance.address
  );

  const wsomInstance = await WarehouseSupplierOrderManagement.deployed();
  console.log("WarehouseSupplierOrderManagement đã được deploy tại:", wsomInstance.address);
};
