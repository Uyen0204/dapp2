// migrations/9_deploy_customer_order.js
const RoleManagement = artifacts.require("RoleManagement");
const ItemsManagementCore = artifacts.require("ItemsManagementCore");
const ItemsPricingAndListing = artifacts.require("ItemsPricingAndListing"); // COM cần cả hai
const CompanyTreasuryManager = artifacts.require("CompanyTreasuryManager");
const CustomerOrderManagement = artifacts.require("CustomerOrderManagement");

module.exports = async function (deployer, network, accounts) {
  const deployerAccount = accounts[0];
  const roleManagementInstance = await RoleManagement.deployed();
  const itemsManagementCoreInstance = await ItemsManagementCore.deployed();
  const itemsPricingAndListingInstance = await ItemsPricingAndListing.deployed();
  const companyTreasuryManagerInstance = await CompanyTreasuryManager.deployed();

  if (!roleManagementInstance) {
    console.error("LỖI: RoleManagement contract chưa được deploy! Không thể deploy COM.");
    return;
  }
  if (!itemsManagementCoreInstance) {
    console.error("LỖI: ItemsManagementCore contract chưa được deploy! Không thể deploy COM.");
    return;
  }
  if (!itemsPricingAndListingInstance) {
    console.error("LỖI: ItemsPricingAndListing contract chưa được deploy! Không thể deploy COM.");
    return;
  }
  if (!companyTreasuryManagerInstance) {
    console.error("LỖI: CompanyTreasuryManager contract chưa được deploy! Không thể deploy COM.");
    return;
  }

  console.log(`Deploying CustomerOrderManagement với:`);
  console.log(`  - RoleManagement tại: ${roleManagementInstance.address}`);
  console.log(`  - ItemsManagementCore tại: ${itemsManagementCoreInstance.address}`);
  console.log(`  - ItemsPricingAndListing tại: ${itemsPricingAndListingInstance.address}`);
  console.log(`  - CompanyTreasuryManager tại: ${companyTreasuryManagerInstance.address}`);

  await deployer.deploy(
    CustomerOrderManagement,
    roleManagementInstance.address,
    itemsManagementCoreInstance.address,
    itemsPricingAndListingInstance.address,
    companyTreasuryManagerInstance.address,
    { from: deployerAccount }
  );

  const comInstance = await CustomerOrderManagement.deployed();
  console.log("CustomerOrderManagement đã được deploy tại:", comInstance.address);
};