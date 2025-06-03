// Import the new contract artifacts
const RoleManagement = artifacts.require("RoleManagement");
const ItemsManagementCore = artifacts.require("ItemsManagementCore"); // Changed
const ItemsPricingAndListing = artifacts.require("ItemsPricingAndListing"); // New
const CompanyTreasuryManager = artifacts.require("CompanyTreasuryManager");
const WarehouseInventoryManagement = artifacts.require("WarehouseInventoryManagement");
const StoreInventoryManagement = artifacts.require("StoreInventoryManagement");
const WarehouseSupplierOrderManagement = artifacts.require("WarehouseSupplierOrderManagement");
const CustomerOrderManagement = artifacts.require("CustomerOrderManagement");

module.exports = async function (deployer, network, accounts) {
  const deployerAccount = accounts[0]; // Admin/Owner account

  let rmInstance, imcInstance, iplInstance, ctmInstance, wimInstance, simInstance, wsomInstance, comInstance;

  try {
    rmInstance = await RoleManagement.deployed();
    imcInstance = await ItemsManagementCore.deployed(); // Changed
    iplInstance = await ItemsPricingAndListing.deployed(); // New
    ctmInstance = await CompanyTreasuryManager.deployed();
    wimInstance = await WarehouseInventoryManagement.deployed();
    simInstance = await StoreInventoryManagement.deployed();
    wsomInstance = await WarehouseSupplierOrderManagement.deployed();
    comInstance = await CustomerOrderManagement.deployed();
  } catch (e) {
    console.error("Error fetching deployed contract instances. Ensure all contracts are deployed in the correct order before running this script.", e);
    return;
  }

  console.log("=== Starting: Set Inter-Contract Addresses ===");

  // 1. RoleManagement (RM) needs CompanyTreasuryManager (CTM) address
  // This is for the activateBoardMemberByTreasury function which has onlyCTM modifier.
  if (rmInstance && ctmInstance) {
    console.log(`Setting CTM address (${ctmInstance.address}) in RoleManagement (${rmInstance.address})...`);
    await rmInstance.setCompanyTreasuryManagerAddress(ctmInstance.address, { from: deployerAccount });
    console.log("  -> CTM address set in RM.");
  } else {
    console.warn("Skipping CTM -> RM: One or both instances not found.");
  }

  // 2. CompanyTreasuryManager (CTM) needs WSOM and COM addresses
  // These are set by the owner for CTM to know who can call escrow/refund functions.
  // CTM's dependencies on RM and IMC are handled via its constructor.
  if (ctmInstance && wsomInstance) {
    console.log(`Setting WSOM address (${wsomInstance.address}) in CTM (${ctmInstance.address})...`);
    await ctmInstance.setWarehouseSupplierOrderManagementAddress(wsomInstance.address, { from: deployerAccount });
    console.log("  -> WSOM address set in CTM.");
  } else {
    console.warn("Skipping WSOM -> CTM: One or both instances not found.");
  }

  if (ctmInstance && comInstance) {
    console.log(`Setting COM address (${comInstance.address}) in CTM (${ctmInstance.address})...`);
    await ctmInstance.setCustomerOrderManagementAddress(comInstance.address, { from: deployerAccount });
    console.log("  -> COM address set in CTM.");
  } else {
    console.warn("Skipping COM -> CTM: One or both instances not found.");
  }

  // 3. WarehouseSupplierOrderManagement (WSOM) needs WarehouseInventoryManagement (WIM) address
  // WSOM's dependencies on RM, IMC, IPL, CTM are via constructor.
  if (wsomInstance && wimInstance) {
    console.log(`Setting WIM address (${wimInstance.address}) in WSOM (${wsomInstance.address})...`);
    await wsomInstance.setWarehouseInventoryManagementAddress(wimInstance.address, { from: deployerAccount });
    console.log("  -> WIM address set in WSOM.");
  } else {
    console.warn("Skipping WIM -> WSOM: One or both instances not found.");
  }
  
  // 4. WarehouseInventoryManagement (WIM) needs SIM, WSOM, and COM addresses
  // WIM's dependencies on RM and IMC are via constructor.
  if (wimInstance && simInstance) {
    console.log(`Setting SIM address (${simInstance.address}) in WIM (${wimInstance.address})...`);
    await wimInstance.setStoreInventoryManagementAddress(simInstance.address, { from: deployerAccount });
    console.log("  -> SIM address set in WIM.");
  } else {
    console.warn("Skipping SIM -> WIM: One or both instances not found.");
  }

  if (wimInstance && wsomInstance) {
    console.log(`Setting WSOM address (${wsomInstance.address}) in WIM (${wimInstance.address})...`);
    await wimInstance.setWarehouseSupplierOrderManagementAddress(wsomInstance.address, { from: deployerAccount });
    console.log("  -> WSOM address set in WIM.");
  } else {
    console.warn("Skipping WSOM -> WIM: One or both instances not found.");
  }

  // WIM also needs COM address for recordReturnedStockByCustomer
  if (wimInstance && comInstance) {
    console.log(`Setting COM address (${comInstance.address}) in WIM (${wimInstance.address})...`);
    await wimInstance.setCustomerOrderManagementAddress(comInstance.address, { from: deployerAccount });
    console.log("  -> COM address set in WIM.");
  } else {
    console.warn("Skipping COM -> WIM: One or both instances not found.");
  }


  // 5. StoreInventoryManagement (SIM) needs WIM and COM addresses
  // SIM's dependencies on RM and IMC are via constructor.
  if (simInstance && wimInstance) {
    console.log(`Setting WIM address (${wimInstance.address}) in SIM (${simInstance.address})...`);
    await simInstance.setWarehouseInventoryManagementAddress(wimInstance.address, { from: deployerAccount });
    console.log("  -> WIM address set in SIM.");
  } else {
    console.warn("Skipping WIM -> SIM: One or both instances not found.");
  }

  if (simInstance && comInstance) {
    console.log(`Setting COM address (${comInstance.address}) in SIM (${simInstance.address})...`);
    await simInstance.setCustomerOrderManagementAddress(comInstance.address, { from: deployerAccount });
    console.log("  -> COM address set in SIM.");
  } else {
    console.warn("Skipping COM -> SIM: One or both instances not found.");
  }

  // 6. CustomerOrderManagement (COM) needs SIM and WIM addresses
  // COM's dependencies on RM, IMC, IPL, CTM are via constructor.
  if (comInstance && simInstance) {
    console.log(`Setting SIM address (${simInstance.address}) in COM (${comInstance.address})...`);
    await comInstance.setStoreInventoryManagementAddress(simInstance.address, { from: deployerAccount });
    console.log("  -> SIM address set in COM.");
  } else {
    console.warn("Skipping SIM -> COM: One or both instances not found.");
  }

  if (comInstance && wimInstance) { // For customer returns
    console.log(`Setting WIM address (${wimInstance.address}) in COM (${comInstance.address})...`);
    await comInstance.setWarehouseInventoryManagementAddress(wimInstance.address, { from: deployerAccount });
    console.log("  -> WIM address set in COM (for returns).");
  } else {
    console.warn("Skipping WIM -> COM (for returns): One or both instances not found.");
  }
  
  // Initial Finance Director Setup for CTM
  if (ctmInstance && rmInstance) {
    const initialFinanceDirector = accounts[1]; // Example: accounts[1] from your test network
    const financeDirectorRoleId = await rmInstance.FINANCE_DIRECTOR_ROLE_ID();
    
    // First, ensure this account has the FINANCE_DIRECTOR_ROLE in RoleManagement
    // This would typically be done by the DEFAULT_ADMIN_ROLE (deployerAccount)
    // For this script, we assume it might need to be granted if not already.
    let hasFinRole = await rmInstance.hasRole(financeDirectorRoleId, initialFinanceDirector);
    if (!hasFinRole) {
        console.warn(`Account ${initialFinanceDirector} does not have FINANCE_DIRECTOR_ROLE. Attempting to grant...`);
        // Granting requires board approval in the full flow. For initial setup, admin might do it.
        // Assuming deployer (admin) can grant this directly or it's a simplified setup.
        // In your RM, granting FINANCE_DIRECTOR_ROLE is done by `grantRoleByBoard` which needs approvers.
        // This step is complex for an automated script without pre-defined board members.
        // For simplicity, let's assume deployer (DEFAULT_ADMIN_ROLE) can grant FINANCE_DIRECTOR_ROLE directly for bootstrapping
        // OR that it's already been granted.
        // Your RM's `grantRoleByBoard` actually uses `onlyActiveBoardMember`. The deployer is an active board member.
        // To make this script runnable, the deployer (accounts[0]) will be the sole approver.
        // This might not meet the >50% share if totalCapital is high and deployer share is low
        // but for initial setup with deployer as the only/main board member, it should work.

        // A more robust setup script would handle board member creation and then role assignment.
        // For now, if the deployer is the sole board member, they can self-approve (or needs to be fixed in RM logic for single approver).
        // Your RM `grantRoleByBoard` has `require(approvers[i] != msg.sender)`
        // This means deployer CANNOT self-approve.
        // SO, THIS ROLE MUST BE GRANTED MANUALLY or by another board member post-deployment for a clean run.
        // We will proceed assuming it's granted or will be granted manually.
        console.warn(`  -> FINANCE_DIRECTOR_ROLE for ${initialFinanceDirector} must be granted manually or by an existing board member (not self-granted by proposer).`);
    }

    hasFinRole = await rmInstance.hasRole(financeDirectorRoleId, initialFinanceDirector); // Re-check
    if (hasFinRole) {
        // Check if Finance Director is already set
        const currentFD = await ctmInstance.financeDirector();
        if (currentFD === "0x0000000000000000000000000000000000000000") {
            console.log(`Setting Initial Finance Director (${initialFinanceDirector}) in CTM (${ctmInstance.address})...`);
            await ctmInstance.setInitialFinanceDirector(initialFinanceDirector, { from: deployerAccount });
            console.log("  -> Initial Finance Director set in CTM.");
        } else {
            console.log(`Initial Finance Director already set in CTM to: ${currentFD}`);
        }
    } else {
        console.warn(`CRITICAL: Account ${initialFinanceDirector} does NOT have FINANCE_DIRECTOR_ROLE.`);
        console.warn(`  -> Initial Finance Director cannot be set in CTM.`);
        console.warn(`  -> Please grant FINANCE_DIRECTOR_ROLE to ${initialFinanceDirector} in RoleManagement by a board member other than the proposer.`);
    }
  } else {
    console.warn("Skipping Initial Finance Director setup: CTM or RM instance not found.");
  }

  console.log("=== Finished: Set Inter-Contract Addresses ===");
};