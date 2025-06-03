// migrations/4_deploy_items_pricing_listing.js
const RoleManagement = artifacts.require("RoleManagement");
const ItemsManagementCore = artifacts.require("ItemsManagementCore");
const ItemsPricingAndListing = artifacts.require("ItemsPricingAndListing");

module.exports = async function (deployer, network, accounts) {
  const roleManagementInstance = await RoleManagement.deployed();
  const itemsManagementCoreInstance = await ItemsManagementCore.deployed();

  if (!roleManagementInstance) {
    console.error("LỖI: RoleManagement contract chưa được deploy! Không thể deploy ItemsPricingAndListing.");
    return;
  }
  if (!itemsManagementCoreInstance) {
    console.error("LỖI: ItemsManagementCore contract chưa được deploy! Không thể deploy ItemsPricingAndListing.");
    return;
  }

  console.log("Deploying ItemsPricingAndListing với:");
  console.log("  - RoleManagement tại:", roleManagementInstance.address);
  console.log("  - ItemsManagementCore tại:", itemsManagementCoreInstance.address);

  await deployer.deploy(
    ItemsPricingAndListing,
    roleManagementInstance.address,
    itemsManagementCoreInstance.address
  );

  const itemsPricingAndListingInstance = await ItemsPricingAndListing.deployed();
  console.log("ItemsPricingAndListing đã được deploy tại:", itemsPricingAndListingInstance.address);
};