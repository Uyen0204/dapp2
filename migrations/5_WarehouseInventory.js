// migrations/5_WarehouseInventory.js (Hoặc tên file của bạn)

const RoleManagement = artifacts.require("RoleManagement");
const ItemsManagement = artifacts.require("ItemsManagement"); // Cần import để lấy instance
const WarehouseInventoryManagement = artifacts.require("WarehouseInventoryManagement");

module.exports = async function (deployer, network, accounts) {
  const deployerAccount = accounts[0];

  // Lấy instance của các contract đã deploy trước đó
  const roleManagementInstance = await RoleManagement.deployed();
  const itemsManagementInstance = await ItemsManagement.deployed(); // BỎ COMMENT VÀ LẤY INSTANCE

  if (!roleManagementInstance) {
    console.error("LỖI: RoleManagement contract chưa được deploy! Không thể deploy WIM.");
    return;
  }
  if (!itemsManagementInstance) { // KIỂM TRA itemsManagementInstance
    console.error("LỖI: ItemsManagement contract chưa được deploy! Không thể deploy WIM.");
    return;
  }

  console.log(`Deploying WarehouseInventoryManagement với:`);
  console.log(`  - RoleManagement tại: ${roleManagementInstance.address}`);
  console.log(`  - ItemsManagement tại: ${itemsManagementInstance.address}`); // Log ra để kiểm tra
  
  await deployer.deploy(
    WarehouseInventoryManagement,
    roleManagementInstance.address,    // Tham số 1 cho constructor
    itemsManagementInstance.address, // Tham số 2 cho constructor
    { from: deployerAccount }          // Object tùy chọn giao dịch
  );

  const wimInstance = await WarehouseInventoryManagement.deployed();
  console.log("WarehouseInventoryManagement đã được deploy tại:", wimInstance.address);

  // LƯU Ý:
  // Các hàm setStoreInventoryManagementAddress và setWarehouseSupplierOrderManagementAddress
  // trên wimInstance sẽ cần được gọi trong một script migration setup chung (ví dụ: 99_setup_addresses.js)
  // sau khi StoreInventoryManagement và WarehouseSupplierOrderManagement đã được deploy.
};