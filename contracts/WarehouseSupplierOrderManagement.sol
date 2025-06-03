// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interfaces.sol";      // Import file Interfaces.sol tập trung
// KHÔNG CẦN: import "./ItemsManagement.sol";

// Hợp đồng Quản lý Đơn hàng Kho - Nhà cung cấp
contract WarehouseSupplierOrderManagement is ReentrancyGuard, Ownable {
    // Sử dụng các interface từ Interfaces.sol
    IRoleManagementInterface public immutable roleManagement;
    // THAY ĐỔI:
    IItemsManagementCoreInterface public immutable itemsManagementCore;
    IItemsPricingAndListingInterface public immutable itemsPricingAndListing;

    ICompanyTreasuryManagerInterface public immutable companyTreasuryManager;
    IWarehouseInventoryManagementInterface public warehouseInventoryManagement;

    uint256 public nextWSOrderId;

    enum WSOrderStatus { PendingShipment, ShippedBySupplier, ReceivedByWarehouse, CancelledByWarehouse, CancelledBySupplier }

    struct WSOrderItem {
        string itemId;
        uint256 quantity;
        uint256 unitPrice;
    }

    struct WSOrder {
        uint256 wsOrderId;
        address warehouseAddress;
        address warehouseManager;
        address supplierAddress;
        WSOrderItem[] items;
        uint256 totalAmount;
        WSOrderStatus status;
        uint256 creationTimestamp;
        uint256 lastUpdateTimestamp;
        bool fundsEscrowed;
        bool fundsReleasedToSupplier;
        string internalSupplierOrderId;
    }

    struct WSOrderItemInput {
        string itemId;
        uint256 quantity;
    }

    mapping(uint256 => WSOrder) public wsOrders;
    mapping(address => uint256[]) public warehouseSentOrderIds;
    mapping(address => uint256[]) public supplierReceivedOrderIds;

    // --- EVENTS ---
    event WSOrderPlaced(uint256 indexed wsOrderId, address indexed warehouseAddress, address indexed supplierAddress, uint256 totalAmount, string internalSupplierOrderId);
    event WSOrderShipmentConfirmedBySupplier(uint256 indexed wsOrderId, address indexed supplierAddress);
    event WSOrderReceiptConfirmedByWarehouse(uint256 indexed wsOrderId, address indexed warehouseManager);
    event WSOrderCancelledByWarehouse(uint256 indexed wsOrderId, address indexed warehouseManager, string reason);
    event WSOrderCancelledBySupplier(uint256 indexed wsOrderId, address indexed supplierAddress, string reason);
    event WSOrderFundsReleasedToSupplier(uint256 indexed wsOrderId, address indexed supplierAddress, uint256 amount);
    event EscrowRequestedForWSOrder(uint256 indexed wsOrderId, uint256 amount, string internalSupplierOrderId);
    event WSOrderStatusUpdated(uint256 indexed wsOrderId, WSOrderStatus newStatus, uint256 timestamp);
    event WarehouseInventoryManagementAddressSet(address indexed wimAddress);

    constructor(
        address _roleManagementAddress,
        // THAY ĐỔI:
        address _itemsManagementCoreAddress,
        address _itemsPricingAndListingAddress,
        address _companyTreasuryManagerAddress
    ) Ownable() {
        require(_roleManagementAddress != address(0), "WSOM: Dia chi RM khong hop le");
        roleManagement = IRoleManagementInterface(_roleManagementAddress);

        // THAY ĐỔI:
        require(_itemsManagementCoreAddress != address(0), "WSOM: Dia chi ItemsMCore khong hop le");
        itemsManagementCore = IItemsManagementCoreInterface(_itemsManagementCoreAddress);
        require(_itemsPricingAndListingAddress != address(0), "WSOM: Dia chi ItemsPL khong hop le");
        itemsPricingAndListing = IItemsPricingAndListingInterface(_itemsPricingAndListingAddress);

        require(_companyTreasuryManagerAddress != address(0), "WSOM: Dia chi CTM khong hop le");
        companyTreasuryManager = ICompanyTreasuryManagerInterface(_companyTreasuryManagerAddress);

        nextWSOrderId = 1;
    }

    function setWarehouseInventoryManagementAddress(address _wimAddress) external onlyOwner {
        require(_wimAddress != address(0), "WSOM: Dia chi WIM khong hop le");
        warehouseInventoryManagement = IWarehouseInventoryManagementInterface(_wimAddress);
        emit WarehouseInventoryManagementAddressSet(_wimAddress);
    }

    modifier onlyWarehouseManagerForAction(address _warehouseAddress) {
        require(_warehouseAddress != address(0), "WSOM: Dia chi kho khong hop le");
        // THAY ĐỔI:
        PhysicalLocationInfo memory warehouseInfo = itemsManagementCore.getWarehouseInfo(_warehouseAddress);
        require(warehouseInfo.exists, "WSOM: Kho khong ton tai");
        require(warehouseInfo.manager == msg.sender, "WSOM: Nguoi goi khong phai quan ly kho nay");
        bytes32 whManagerRole = roleManagement.WAREHOUSE_MANAGER_ROLE();
        require(roleManagement.hasRole(whManagerRole, msg.sender), "WSOM: Nguoi goi thieu vai tro QUAN_LY_KHO");
        _;
    }

    modifier onlyOrderWarehouseManager(uint256 _wsOrderId) {
        WSOrder storage currentOrder = wsOrders[_wsOrderId];
        require(currentOrder.wsOrderId != 0, "WSOM: Don hang khong ton tai");
        require(currentOrder.warehouseManager == msg.sender, "WSOM: Nguoi goi khong phai quan ly kho cua don hang");
        bytes32 whManagerRole = roleManagement.WAREHOUSE_MANAGER_ROLE();
        require(roleManagement.hasRole(whManagerRole, msg.sender), "WSOM: Nguoi goi thieu vai tro QUAN_LY_KHO");
        _;
    }

    modifier onlyOrderSupplier(uint256 _wsOrderId) {
        WSOrder storage currentOrder = wsOrders[_wsOrderId];
        require(currentOrder.wsOrderId != 0, "WSOM: Don hang khong ton tai");
        require(currentOrder.supplierAddress == msg.sender, "WSOM: Nguoi goi khong phai NCC cua don hang");
        bytes32 supRole = roleManagement.SUPPLIER_ROLE();
        require(roleManagement.hasRole(supRole, msg.sender), "WSOM: Nguoi goi thieu vai tro NCC");
        _;
    }

    function _processOrderItems(
        WSOrderItemInput[] calldata _itemsInput,
        address _supplierAddress,
        WSOrderItem[] storage _orderItems
    ) internal returns (uint256 calculatedTotalAmount) {
        calculatedTotalAmount = 0;
        for (uint i = 0; i < _itemsInput.length; i++) {
            WSOrderItemInput calldata itemInput = _itemsInput[i];
            require(itemInput.quantity > 0, "WSOM: So luong mat hang phai la so duong");
            // THAY ĐỔI:
            SupplierItemListing memory supplierListing = itemsPricingAndListing.getSupplierItemDetails(_supplierAddress, itemInput.itemId);
            require(supplierListing.exists && supplierListing.isApprovedByBoard, "WSOM: Mat hang cua NCC khong co san hoac chua duoc phe duyet boi BDH");
            _orderItems.push(WSOrderItem({
                itemId: itemInput.itemId,
                quantity: itemInput.quantity,
                unitPrice: supplierListing.price
            }));
            calculatedTotalAmount += supplierListing.price * itemInput.quantity;
        }
    }

    function _validateAndRequestEscrow(
        address _warehouseAddress,
        address _supplierAddress,
        string memory _internalOrderId,
        uint256 _orderTotal
    ) internal returns (bool) {
        uint256 maxAmountPerOrderPolicy = companyTreasuryManager.getWarehouseSpendingPolicy(_warehouseAddress, _supplierAddress);
        uint256 currentSpendingThisPeriod = companyTreasuryManager.getWarehouseSpendingThisPeriod(_warehouseAddress);
        uint256 spendingLimitPerPeriod = companyTreasuryManager.WAREHOUSE_SPENDING_LIMIT_PER_PERIOD_CONST();
        require(maxAmountPerOrderPolicy > 0, "WSOM: Khong co chinh sach chi tieu tu Ngan quy cho kho/ncc nay");
        require(_orderTotal <= maxAmountPerOrderPolicy, "WSOM: Gia tri don hang vuot qua chinh sach chi tieu moi don hang");
        uint256 projectedSpending = currentSpendingThisPeriod + _orderTotal;
        require(projectedSpending <= spendingLimitPerPeriod, "WSOM: Don hang vuot qua gioi han chi tieu dinh ky cua kho");
        bool escrowSuccess = companyTreasuryManager.requestEscrowForSupplierOrder(
            _warehouseAddress, _supplierAddress, _internalOrderId, _orderTotal
        );
        emit EscrowRequestedForWSOrder(wsOrders[nextWSOrderId-1].wsOrderId, _orderTotal, _internalOrderId);
        return escrowSuccess;
    }

    function uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        uint256 i = digits;
        while (value != 0) { i--; buffer[i] = bytes1(uint8(48 + (value % 10))); value /= 10; }
        return string(buffer);
    }

    function placeOrderByWarehouse(
        address _warehouseAddress,
        address _supplierAddress,
        WSOrderItemInput[] calldata _itemsInput
    ) external onlyWarehouseManagerForAction(_warehouseAddress) nonReentrant {
        require(address(warehouseInventoryManagement) != address(0), "WSOM: Dia chi WIM chua duoc dat");
        require(_itemsInput.length > 0, "WSOM: Don hang phai co it nhat mot mat hang");

        // THAY ĐỔI:
        SupplierInfo memory supplierInfo = itemsManagementCore.getSupplierInfo(_supplierAddress);
        require(supplierInfo.exists && supplierInfo.isApprovedByBoard, "WSOM: NCC khong hop le hoac chua duoc phe duyet");

        uint256 currentWsOrderId = nextWSOrderId++;
        string memory internalOrderIdForEscrow = string(abi.encodePacked("WSOM-ORDER-", uintToString(currentWsOrderId)));
        WSOrder storage newOrder = wsOrders[currentWsOrderId];
        newOrder.wsOrderId = currentWsOrderId;
        newOrder.warehouseAddress = _warehouseAddress;
        newOrder.warehouseManager = msg.sender;
        newOrder.supplierAddress = _supplierAddress;
        newOrder.status = WSOrderStatus.PendingShipment;
        newOrder.creationTimestamp = block.timestamp;
        newOrder.lastUpdateTimestamp = block.timestamp;
        newOrder.internalSupplierOrderId = internalOrderIdForEscrow;
        newOrder.totalAmount = _processOrderItems(_itemsInput, _supplierAddress, newOrder.items);
        require(newOrder.totalAmount > 0, "WSOM: Tong gia tri don hang phai lon hon 0");
        bool escrowSuccess = _validateAndRequestEscrow(
            _warehouseAddress,
            _supplierAddress,
            internalOrderIdForEscrow,
            newOrder.totalAmount
        );
        require(escrowSuccess, "WSOM: Ky quy tien tu CTM that bai");
        newOrder.fundsEscrowed = true;
        warehouseSentOrderIds[_warehouseAddress].push(currentWsOrderId);
        supplierReceivedOrderIds[_supplierAddress].push(currentWsOrderId);
        emit WSOrderPlaced(currentWsOrderId, _warehouseAddress, _supplierAddress, newOrder.totalAmount, internalOrderIdForEscrow);
        emit WSOrderStatusUpdated(currentWsOrderId, newOrder.status, block.timestamp);
    }

    function supplierConfirmShipment(uint256 _wsOrderId) external onlyOrderSupplier(_wsOrderId) nonReentrant {
        WSOrder storage currentOrder = wsOrders[_wsOrderId];
        require(currentOrder.status == WSOrderStatus.PendingShipment, "WSOM: Don hang khong o trang thai cho giao hang");
        currentOrder.status = WSOrderStatus.ShippedBySupplier;
        currentOrder.lastUpdateTimestamp = block.timestamp;
        emit WSOrderShipmentConfirmedBySupplier(_wsOrderId, msg.sender);
        emit WSOrderStatusUpdated(_wsOrderId, currentOrder.status, block.timestamp);
    }

    function warehouseConfirmReceipt(uint256 _wsOrderId) external onlyOrderWarehouseManager(_wsOrderId) nonReentrant {
        WSOrder storage currentOrder = wsOrders[_wsOrderId];
        require(currentOrder.status == WSOrderStatus.ShippedBySupplier, "WSOM: Don hang chua duoc NCC giao");
        require(currentOrder.fundsEscrowed, "WSOM: Tien chua duoc ky quy cho don hang nay");
        require(!currentOrder.fundsReleasedToSupplier, "WSOM: Tien da duoc giai ngan cho NCC roi");
        require(address(warehouseInventoryManagement) != address(0), "WSOM: Dia chi WIM chua duoc dat");
        bool releaseSuccess = companyTreasuryManager.releaseEscrowToSupplier(
            currentOrder.supplierAddress,
            currentOrder.internalSupplierOrderId,
            currentOrder.totalAmount
        );
        require(releaseSuccess, "WSOM: Giai ngan tien cho NCC tu CTM that bai");
        currentOrder.status = WSOrderStatus.ReceivedByWarehouse;
        currentOrder.fundsReleasedToSupplier = true;
        currentOrder.lastUpdateTimestamp = block.timestamp;
        for (uint i = 0; i < currentOrder.items.length; i++) {
            WSOrderItem memory item = currentOrder.items[i];
            warehouseInventoryManagement.recordStockInFromSupplier(
                currentOrder.warehouseAddress,
                item.itemId,
                item.quantity,
                _wsOrderId
            );
        }
        emit WSOrderReceiptConfirmedByWarehouse(_wsOrderId, msg.sender);
        emit WSOrderFundsReleasedToSupplier(_wsOrderId, currentOrder.supplierAddress, currentOrder.totalAmount);
        emit WSOrderStatusUpdated(_wsOrderId, currentOrder.status, block.timestamp);
    }

    function _internalCancelOrder(uint256 _wsOrderId, WSOrderStatus _newStatus, address) internal {
        WSOrder storage currentOrder = wsOrders[_wsOrderId];
        require(currentOrder.status == WSOrderStatus.PendingShipment, "WSOM: Don hang khong o trang thai co the huy");
        require(currentOrder.fundsEscrowed, "WSOM: Tien chua duoc ky quy (hoac da bi huy) de huy");
        bool refundSuccess = companyTreasuryManager.refundEscrowToTreasury(
            currentOrder.warehouseAddress,
            currentOrder.internalSupplierOrderId,
            currentOrder.totalAmount
        );
        require(refundSuccess, "WSOM: Hoan tra tien ky quy ve CTM that bai, viec huy bi hoan tac");
        currentOrder.status = _newStatus;
        currentOrder.fundsEscrowed = false;
        currentOrder.lastUpdateTimestamp = block.timestamp;
        emit WSOrderStatusUpdated(_wsOrderId, currentOrder.status, block.timestamp);
    }

    function cancelOrderByWarehouse(uint256 _wsOrderId, string calldata _reason)
        external
        onlyOrderWarehouseManager(_wsOrderId)
        nonReentrant
    {
        _internalCancelOrder(_wsOrderId, WSOrderStatus.CancelledByWarehouse, msg.sender);
        emit WSOrderCancelledByWarehouse(_wsOrderId, msg.sender, _reason);
    }

    function cancelOrderBySupplier(uint256 _wsOrderId, string calldata _reason)
        external
        onlyOrderSupplier(_wsOrderId)
        nonReentrant
    {
        _internalCancelOrder(_wsOrderId, WSOrderStatus.CancelledBySupplier, msg.sender);
        emit WSOrderCancelledBySupplier(_wsOrderId, msg.sender, _reason);
    }

    function getWSOrderDetails(uint256 _wsOrderId) external view returns (WSOrder memory) {
        require(wsOrders[_wsOrderId].wsOrderId != 0, "WSOM: Don hang khong tim thay");
        return wsOrders[_wsOrderId];
    }

    function getWarehouseSentOrders(address _warehouseAddress) external view returns (uint256[] memory) {
        return warehouseSentOrderIds[_warehouseAddress];
    }

    function getSupplierReceivedOrders(address _supplierAddress) external view returns (uint256[] memory) {
        return supplierReceivedOrderIds[_supplierAddress];
    }
}