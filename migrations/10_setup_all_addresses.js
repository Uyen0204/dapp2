```javascript
// migrations/10_setup_all_addresses.js
const RoleManagement = artifacts.require("RoleManagement");
// Lấy ItemsManagementCore và ItemsPricingAndListing nếu cần tương tác trực tiếp trong script này
// const ItemsManagementCore = artifacts.require("ItemsManagementCore");
// const ItemsPricingAndListing = artifacts.require("ItemsPricingAndListing");
const CompanyTreasuryManager = artifacts.require("CompanyTreasuryManager");
const WarehouseInventoryManagement = artifacts.require("WarehouseInventoryManagement");
const StoreInventoryManagement = artifacts.require("StoreInventoryManagement");
const WarehouseSupplierOrderManagement = artifacts.require("WarehouseSupplierOrderManagement");
const CustomerOrderManagement = artifacts.require("CustomerOrderManagement");

module.exports = async function (deployer, network, accounts) {
  const deployerAccount = accounts[0];

  let rmInstance, ctmInstance, wimInstance, simInstance, wsomInstance, comInstance;
  // Không cần imcInstance, iplInstance ở đây trừ khi bạn muốn gọi hàm view của chúng
  // let imcInstance, iplInstance;


  try {
    rmInstance = await RoleManagement.deployed();
    // imcInstance = await ItemsManagementCore.deployed(); // Chỉ lấy nếu cần
    // iplInstance = await ItemsPricingAndListing.deployed(); // Chỉ lấy nếu cần
    ctmInstance = await CompanyTreasuryManager.deployed();
    wimInstance = await WarehouseInventoryManagement.deployed();
    simInstance = await StoreInventoryManagement.deployed();
    wsomInstance = await WarehouseSupplierOrderManagement.deployed();
    comInstance = await CustomerOrderManagement.deployed();
  } catch (e) {
    console.error("Lỗi khi lấy instance của một hoặc nhiều contract đã deploy. Đảm bảo tất cả đã được deploy trước khi chạy script này.", e);
    return;
  }

  const allInstancesAvailable = rmInstance && ctmInstance && wimInstance && simInstance && wsomInstance && comInstance;

  if (!allInstancesAvailable) {
      console.error("Một hoặc nhiều contract chính chưa được deploy. Không thể tiếp tục script setup.");
      if (!rmInstance) console.error("RoleManagement instance is missing.");
      // if (!imcInstance) console.error("ItemsManagementCore instance is missing."); // Nếu bạn lấy nó
      // if (!iplInstance) console.error("ItemsPricingAndListing instance is missing."); // Nếu bạn lấy nó
      if (!ctmInstance) console.error("CompanyTreasuryManager instance is missing.");
      if (!wimInstance) console.error("WarehouseInventoryManagement instance is missing.");
      if (!simInstance) console.error("StoreInventoryManagement instance is missing.");
      if (!wsomInstance) console.error("WarehouseSupplierOrderManagement instance is missing.");
      if (!comInstance) console.error("CustomerOrderManagement instance is missing.");
      return;
  }


  console.log("=== Bắt đầu thiết lập liên kết địa chỉ giữa các contract ===");

  // 1. RoleManagement
  console.log(`Thiết lập CTM address (${ctmInstance.address}) cho RoleManagement...`);
  await rmInstance.setCompanyTreasuryManagerAddress(ctmInstance.address, { from: deployerAccount });
  console.log("  -> Đã thiết lập CTM cho RM.");

  // 2. CompanyTreasuryManager (CTM)
  console.log(`Thiết lập WSOM address (${wsomInstance.address}) cho CTM...`);
  await ctmInstance.setWarehouseSupplierOrderManagementAddress(wsomInstance.address, { from: deployerAccount });
  console.log("  -> Đã thiết lập WSOM cho CTM.");

  console.log(`Thiết lập COM address (${comInstance.address}) cho CTM...`);
  await ctmInstance.setCustomerOrderManagementAddress(comInstance.address, { from: deployerAccount });
  console.log("  -> Đã thiết lập COM cho CTM.");

  // 3. WarehouseSupplierOrderManagement (WSOM)
  console.log(`Thiết lập WIM address (${wimInstance.address}) cho WSOM...`);
  await wsomInstance.setWarehouseInventoryManagementAddress(wimInstance.address, { from: deployerAccount });
  console.log("  -> Đã thiết lập WIM cho WSOM.");

  // 4. WarehouseInventoryManagement (WIM)
  console.log(`Thiết lập SIM address (${simInstance.address}) cho WIM...`);
  await wimInstance.setStoreInventoryManagementAddress(simInstance.address, { from: deployerAccount });
  console.log("  -> Đã thiết lập SIM cho WIM.");

  console.log(`Thiết lập WSOM address (${wsomInstance.address}) cho WIM...`);
  await wimInstance.setWarehouseSupplierOrderManagementAddress(wsomInstance.address, { from: deployerAccount });
  console.log("  -> Đã thiết lập WSOM cho WIM.");
  
  console.log(`Thiết lập COM address (${comInstance.address}) cho WIM (cho returns)...`); // Thêm nếu WIM có hàm setCustomerOrderManagementAddress
  await wimInstance.setCustomerOrderManagementAddress(comInstance.address, { from: deployerAccount });
  console.log("  -> Đã thiết lập COM cho WIM (returns).");


  // 5. StoreInventoryManagement (SIM)
  console.log(`Thiết lập WIM address (${wimInstance.address}) cho SIM...`);
  await simInstance.setWarehouseInventoryManagementAddress(wimInstance.address, { from: deployerAccount });
  console.log("  -> Đã thiết lập WIM cho SIM.");

  console.log(`Thiết lập COM address (${comInstance.address}) cho SIM...`); // Thêm nếu SIM có hàm setCustomerOrderManagementAddress
  await simInstance.setCustomerOrderManagementAddress(comInstance.address, { from: deployerAccount });
  console.log("  -> Đã thiết lập COM cho SIM.");


  // 6. CustomerOrderManagement (COM)
  console.log(`Thiết lập SIM address (${simInstance.address}) cho COM...`);
  await comInstance.setStoreInventoryManagementAddress(simInstance.address, { from: deployerAccount });
  console.log("  -> Đã thiết lập SIM cho COM.");

  console.log(`Thiết lập WIM address (${wimInstance.address}) cho COM (cho returns)...`);
  await comInstance.setWarehouseInventoryManagementAddress(wimInstance.address, { from: deployerAccount });
  console.log("  -> Đã thiết lập WIM cho COM (returns).");

  // Thiết lập Giám đốc Tài chính ban đầu cho CTM
  const initialFinanceDirector = accounts[1]; // Ví dụ
  const financeDirectorRoleId = await rmInstance.FINANCE_DIRECTOR_ROLE(); // Lấy ID vai trò từ RM
  const hasFinRole = await rmInstance.hasRole(financeDirectorRoleId, initialFinanceDirector);

  if (hasFinRole) {
      console.log(`Thiết lập Giám đốc Tài chính ban đầu (${initialFinanceDirector}) cho CTM...`);
      // Kiểm tra xem CTM đã có GĐTC chưa trước khi set
      const currentFinDirector = await ctmInstance.financeDirector();
      if (currentFinDirector === "0x0000000000000000000000000000000000000000") {
        await ctmInstance.setInitialFinanceDirector(initialFinanceDirector, { from: deployerAccount });
        console.log("  -> Đã thiết lập Giám đốc Tài chính.");
      } else {
        console.log(`  -> GĐTC đã được thiết lập: ${currentFinDirector}. Bỏ qua setInitialFinanceDirector.`);
      }
  } else {
      console.warn(`CẢNH BÁO: Tài khoản ${initialFinanceDirector} chưa có vai trò FINANCE_DIRECTOR_ROLE. Không thể thiết lập làm GĐTC ban đầu cho CTM.`);
      console.warn(`  -> Vui lòng cấp vai trò FINANCE_DIRECTOR_ROLE cho ${initialFinanceDirector} trong RoleManagement trước (ví dụ: dùng truffle console).`);
  }

  console.log("=== Hoàn tất thiết lập liên kết địa chỉ và các thiết lập cơ bản ===");
};
```
