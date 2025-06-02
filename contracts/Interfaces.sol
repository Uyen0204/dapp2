// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// --- Forward declare structs ---
// (Giữ nguyên như cũ)
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

// Thêm ItemInfo vào đây vì nó cũng cần được các contract khác biết
struct ItemInfo {
    string itemId;
    string name;
    string description;
    string category;
    bool exists;
    bool isApprovedByBoard;
    address proposer; // Thành viên BĐH đề xuất
    uint256 referencePriceCeiling; // Giá trần tham khảo do BĐH đặt
}


// --- Interfaces for RoleManagement ---
// (Giữ nguyên như cũ)
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

interface IRoleManagementInterface { // Giữ nguyên
    function WAREHOUSE_MANAGER_ROLE() external view returns (bytes32);
    function SUPPLIER_ROLE() external view returns (bytes32);
    function STORE_MANAGER_ROLE() external view returns (bytes32);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function hasRole(bytes32 role, address account) external view returns (bool);
}


// --- Interface for ItemsManagementCore ---
interface IItemsManagementCoreInterface {
    // Functions related to ItemInfo, PhysicalLocationInfo, SupplierInfo
    function getItemInfo(string calldata itemId) external view returns (ItemInfo memory);
    function getPhysicalLocationInfo(address locationId) external view returns (PhysicalLocationInfo memory);
    function getStoreInfo(address storeAddress) external view returns (PhysicalLocationInfo memory);
    function getWarehouseInfo(address warehouseAddress) external view returns (PhysicalLocationInfo memory);
    function getSupplierInfo(address supplierId) external view returns (SupplierInfo memory);
    function getAllItemIds() external view returns (string[] memory);
    function getAllLocationAddresses() external view returns (address[] memory);
    function getAllSupplierAddresses() external view returns (address[] memory);
    // Thêm các hàm getter khác nếu cần cho các contract khác
}

// --- Interface for ItemsPricingAndListing ---
interface IItemsPricingAndListingInterface {
    // Functions related to SupplierItemListing, storeItemRetailPrices
    function getSupplierItemDetails(address supplierAddress, string calldata itemId) external view returns (SupplierItemListing memory);
    function getItemRetailPriceAtStore(string calldata itemId, address storeAddress) external view returns (uint256 price, bool priceExists);
    // Thêm các hàm getter khác nếu cần cho các contract khác
}


// --- Interface for CompanyTreasuryManager ---
// (Giữ nguyên như cũ, nhưng sẽ sử dụng IItemsManagementCoreInterface bên trong)
interface ICompanyTreasuryManagerInterface {
    function requestEscrowForSupplierOrder(address warehouseAddress, address supplierAddress, string calldata supplierOrderId, uint256 amount) external returns (bool success);
    function releaseEscrowToSupplier(address supplierAddress, string calldata supplierOrderId, uint256 amount) external returns (bool success);
    function refundEscrowToTreasury(address warehouseAddress, string calldata supplierOrderId, uint256 amount) external returns (bool success);
    function getWarehouseSpendingPolicy(address warehouseAddress, address supplierAddress) external view returns (uint256 maxAmountPerOrder);
    function getWarehouseSpendingThisPeriod(address warehouseAddress) external view returns (uint256 currentSpending);
    function WAREHOUSE_SPENDING_LIMIT_PER_PERIOD_CONST() external view returns (uint256 limit);
    function refundCustomerOrderFromTreasury(uint256 orderId, address payable customerAddress, uint256 amountToRefund) external;
}

// --- Interface for WarehouseInventoryManagement ---
// (Giữ nguyên như cũ)
interface IWarehouseInventoryManagementInterface {
    function requestStockTransferToStore(
        address requestingStoreManager,
        address storeAddress,
        address designatedWarehouseAddress,
        string calldata itemId,
        uint256 quantity
    ) external returns (uint256 internalTransferId);
    function recordStockInFromSupplier(address warehouseAddress, string calldata itemId, uint256 quantity, uint256 wsOrderId) external;
     function recordReturnedStockByCustomer(
        address returnToWarehouseAddress,
        string calldata itemId,
        uint256 quantity,
        uint256 customerOrderId
    ) external;
}

// --- Interface for StoreInventoryManagement ---
// (Giữ nguyên như cũ)
interface IStoreInventoryManagementInterface {
    function confirmStockReceivedFromWarehouse(
        address storeAddress,
        string calldata itemId,
        uint256 quantity,
        address fromWarehouseAddress,
        uint256 internalTransferId
    ) external;
    function getStoreStockLevel(address storeAddress, string calldata itemId) external view returns (uint256);
    function deductStockForCustomerSale(address storeAddress, string calldata itemId, uint256 quantity, uint256 customerOrderId) external;
}
