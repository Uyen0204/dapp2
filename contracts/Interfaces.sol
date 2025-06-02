// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// --- Forward declare structs that will be defined in ItemsManagement.sol ---
// This helps Interfaces.sol compile and allows other contracts to understand
// the shape of data returned by interface functions.
// The "real" struct definitions are in ItemsManagement.sol.
// MAKE SURE THESE MATCH THE STRUCTS IN ItemsManagement.sol EXACTLY!

struct PhysicalLocationInfo {
    address locationId;
    string name;
    string locationType; // "STORE" hoặc "WAREHOUSE"
    address manager;      // Quản lý (Store Manager / Warehouse Manager)
    bool exists;
    bool isApprovedByBoard; // Được duyệt bởi BĐH
    address designatedSourceWarehouseAddress; // Kho nguồn cho cửa hàng
}

struct SupplierInfo {
    address supplierId;
    string name;
    bool isApprovedByBoard; // Được duyệt bởi BĐH
    bool exists;
}

struct SupplierItemListing {
    string itemId;
    address supplierAddress;
    uint256 price;
    bool isApprovedByBoard; // Duyệt tự động hoặc thủ công bởi BĐH
    bool exists;
}

// --- Interfaces for RoleManagement ---

interface IRoleManagement {
    function STORE_DIRECTOR_ROLE() external view returns (bytes32);
    function WAREHOUSE_DIRECTOR_ROLE() external view returns (bytes32);
    function STORE_MANAGER_ROLE() external view returns (bytes32);
    function WAREHOUSE_MANAGER_ROLE() external view returns (bytes32);
    function BOARD_ROLE() external view returns (bytes32);
    function SUPPLIER_ROLE() external view returns (bytes32);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function FINANCE_DIRECTOR_ROLE() external view returns (bytes32);

    function hasRole(bytes32 role, address account) external view returns (bool);
    function getSharesPercentage(address account) external view returns (uint256);

    function activateBoardMemberByTreasury(address candidate, uint256 contributedAmount) external;
    function getProposedShareCapital(address candidate) external view returns (uint256);
}

// This interface is used by several contracts for more general role checks.
interface IRoleManagementInterface {
    function WAREHOUSE_MANAGER_ROLE() external view returns (bytes32);
    function SUPPLIER_ROLE() external view returns (bytes32);
    function STORE_MANAGER_ROLE() external view returns (bytes32);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function hasRole(bytes32 role, address account) external view returns (bool);
}


// --- Interfaces for ItemsManagement ---
// Now uses the locally forward-declared struct names
interface IItemsManagementInterface {
    function getWarehouseInfo(address warehouseAddress) external view returns (PhysicalLocationInfo memory);
    function getSupplierInfo(address supplierAddress) external view returns (SupplierInfo memory);
    function getStoreInfo(address storeAddress) external view returns (PhysicalLocationInfo memory);
    function getSupplierItemDetails(address supplierAddress, string calldata itemId) external view returns (SupplierItemListing memory);
    function getItemRetailPriceAtStore(string calldata itemId, address storeAddress) external view returns (uint256 price, bool priceExists);
}


// --- Interface for CompanyTreasuryManager ---
interface ICompanyTreasuryManagerInterface {
    // For WarehouseSupplierOrderManagement
    function requestEscrowForSupplierOrder(address warehouseAddress, address supplierAddress, string calldata supplierOrderId, uint256 amount) external returns (bool success);
    function releaseEscrowToSupplier(address supplierAddress, string calldata supplierOrderId, uint256 amount) external returns (bool success);
    function refundEscrowToTreasury(address warehouseAddress, string calldata supplierOrderId, uint256 amount) external returns (bool success);
    function getWarehouseSpendingPolicy(address warehouseAddress, address supplierAddress) external view returns (uint256 maxAmountPerOrder);
    function getWarehouseSpendingThisPeriod(address warehouseAddress) external view returns (uint256 currentSpending);
    function WAREHOUSE_SPENDING_LIMIT_PER_PERIOD_CONST() external view returns (uint256 limit);

    // For CustomerOrderManagement
    function refundCustomerOrderFromTreasury(uint256 orderId, address payable customerAddress, uint256 amountToRefund) external;
}

// --- Interface for WarehouseInventoryManagement ---
interface IWarehouseInventoryManagementInterface {
    // For StoreInventoryManagement
    function requestStockTransferToStore(
        address requestingStoreManager,
        address storeAddress,
        address designatedWarehouseAddress,
        string calldata itemId,
        uint256 quantity
    ) external returns (uint256 internalTransferId);

    // For WarehouseSupplierOrderManagement
    function recordStockInFromSupplier(address warehouseAddress, string calldata itemId, uint256 quantity, uint256 wsOrderId) external;

    // For CustomerOrderManagement (returns)
     function recordReturnedStockByCustomer(
        address returnToWarehouseAddress,
        string calldata itemId,
        uint256 quantity,
        uint256 customerOrderId
    ) external;
}

// --- Interface for StoreInventoryManagement ---
interface IStoreInventoryManagementInterface {
    // For WarehouseInventoryManagement
    function confirmStockReceivedFromWarehouse(
        address storeAddress,
        string calldata itemId,
        uint256 quantity,
        address fromWarehouseAddress,
        uint256 internalTransferId
    ) external;

    // For CustomerOrderManagement
    function getStoreStockLevel(address storeAddress, string calldata itemId) external view returns (uint256);
    function deductStockForCustomerSale(address storeAddress, string calldata itemId, uint256 quantity, uint256 customerOrderId) external;
}