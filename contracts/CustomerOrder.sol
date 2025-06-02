// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interfaces.sol";      // Import file Interfaces.sol tập trung
// KHÔNG CẦN: import "./ItemsManagement.sol";

// Hợp đồng Quản lý Đơn hàng Khách hàng
contract CustomerOrderManagement is ReentrancyGuard, Ownable {
    // Sử dụng các interface từ Interfaces.sol
    IRoleManagementInterface public immutable roleManagement;
    // THAY ĐỔI:
    IItemsManagementCoreInterface public immutable itemsManagementCore;
    IItemsPricingAndListingInterface public immutable itemsPricingAndListing;

    IStoreInventoryManagementInterface public storeInventoryManagement;
    IWarehouseInventoryManagementInterface public warehouseInventoryManagement;
    ICompanyTreasuryManagerInterface public immutable companyTreasuryManager;

    uint256 public nextOrderId;

    enum OrderStatus { Placed, ProcessingByStore, AllItemsReadyForDelivery, DeliveryConfirmedByStore, Completed, CancelledByStore, CancelledByCustomer, ReturnedByCustomer }
    enum OrderItemStatus { PendingStoreProcessing, StoreStockAvailable, StoreNeedsRestock, ReadyForDelivery, DeliveredToCustomer }

    struct OrderItem {
        string itemId;
        uint256 quantity;
        uint256 unitPrice;
        OrderItemStatus status;
    }

    struct Order {
        uint256 orderId;
        address customerAddress;
        address storeAddress;
        OrderItem[] items;
        uint256 totalAmountPaid;
        OrderStatus status;
        uint256 creationTimestamp;
        uint256 lastUpdateTimestamp;
        bool fundsReleasedToCompany;
    }

    struct OrderItemInput {
        string itemId;
        uint256 quantity;
    }

    mapping(uint256 => Order) public orders;
    mapping(address => uint256[]) public customerOrderIds;
    mapping(address => uint256[]) public storeAssignedOrderIds;

    // --- EVENTS ---
    event OrderPlaced(uint256 indexed orderId, address indexed customer, address indexed storeAddress, uint256 totalAmount);
    event OrderItemStatusUpdatedByStore(uint256 indexed orderId, uint256 itemIndexInOrder, string itemId, OrderItemStatus newItemStatus, address indexed byStoreManager);
    event OrderReadyForDelivery(uint256 indexed orderId, address indexed storeAddress, address indexed byStoreManager);
    event OrderDeliveryConfirmedByStore(uint256 indexed orderId, address indexed storeAddress, address indexed byStoreManager);
    event OrderCompletedByCustomer(uint256 indexed orderId, address indexed customer);
    event FundsReleasedToCompanyTreasury(uint256 indexed orderId, uint256 amount, address indexed treasuryAddress);
    event OrderOverallStatusUpdated(uint256 indexed orderId, OrderStatus newStatus, uint256 timestamp);
    event OrderCancelled(uint256 indexed orderId, address indexed canceller, OrderStatus newStatus, string reason, uint256 amountRefunded);
    event OrderReturnProcessed(uint256 indexed orderId, address indexed customer, address returnToWarehouse, string reason);
    event StoreInventoryManagementAddressSet(address indexed simAddress);
    event WarehouseInventoryManagementAddressSet(address indexed wimAddress);

    constructor(
        address _roleManagementAddress,
        // THAY ĐỔI:
        address _itemsManagementCoreAddress,
        address _itemsPricingAndListingAddress,
        address _companyTreasuryManagerAddress
    ) Ownable() {
        require(_roleManagementAddress != address(0), "COM: Dia chi RM khong hop le");
        roleManagement = IRoleManagementInterface(_roleManagementAddress);

        // THAY ĐỔI:
        require(_itemsManagementCoreAddress != address(0), "COM: Dia chi ItemsMCore khong hop le");
        itemsManagementCore = IItemsManagementCoreInterface(_itemsManagementCoreAddress);
        require(_itemsPricingAndListingAddress != address(0), "COM: Dia chi ItemsPL khong hop le");
        itemsPricingAndListing = IItemsPricingAndListingInterface(_itemsPricingAndListingAddress);

        require(_companyTreasuryManagerAddress != address(0), "COM: Dia chi CTM khong hop le");
        companyTreasuryManager = ICompanyTreasuryManagerInterface(_companyTreasuryManagerAddress);

        nextOrderId = 1;
    }

    function setStoreInventoryManagementAddress(address _simAddress) external onlyOwner {
        require(_simAddress != address(0), "COM: Dia chi SIM khong hop le");
        storeInventoryManagement = IStoreInventoryManagementInterface(_simAddress);
        emit StoreInventoryManagementAddressSet(_simAddress);
    }

    function setWarehouseInventoryManagementAddress(address _wimAddress) external onlyOwner {
        require(_wimAddress != address(0), "COM: Dia chi WIM khong hop le");
        warehouseInventoryManagement = IWarehouseInventoryManagementInterface(_wimAddress);
        emit WarehouseInventoryManagementAddressSet(_wimAddress);
    }

    modifier onlyOrderCustomer(uint256 _orderId) {
        Order storage currentOrder = orders[_orderId];
        require(currentOrder.orderId != 0, "COM: Don hang khong ton tai");
        require(currentOrder.customerAddress == msg.sender, "COM: Nguoi goi khong phai la khach hang cua don hang");
        _;
    }

    modifier onlyStoreManagerForOrder(uint256 _orderId) {
        Order storage currentOrder = orders[_orderId];
        require(currentOrder.orderId != 0, "COM: Don hang khong ton tai");
        address storeAddr = currentOrder.storeAddress;
        require(storeAddr != address(0), "COM: Don hang khong co cua hang duoc gan");

        // THAY ĐỔI:
        PhysicalLocationInfo memory storeInfo = itemsManagementCore.getStoreInfo(storeAddr);
        require(storeInfo.manager == msg.sender, "COM: Nguoi goi khong phai quan ly cua hang cua don hang");

        bytes32 smRole = roleManagement.STORE_MANAGER_ROLE();
        require(roleManagement.hasRole(smRole, msg.sender), "COM: Nguoi goi thieu vai tro QUAN_LY_CH");
        _;
    }

    function placeOrder(
        OrderItemInput[] calldata _orderItemsInput,
        address _storeAddress
    ) external payable nonReentrant {
        require(address(storeInventoryManagement) != address(0), "COM: Dia chi SIM chua duoc dat");
        require(_storeAddress != address(0), "COM: Dia chi cua hang khong hop le");
        require(_orderItemsInput.length > 0, "COM: Don hang phai co it nhat mot mat hang");

        // THAY ĐỔI:
        PhysicalLocationInfo memory storeInfo = itemsManagementCore.getStoreInfo(_storeAddress);
        require(storeInfo.exists, "COM: Cua hang khong ton tai");

        uint256 currentOrderId = nextOrderId++;
        Order storage newOrder = orders[currentOrderId];
        newOrder.orderId = currentOrderId;
        newOrder.customerAddress = msg.sender;
        newOrder.storeAddress = _storeAddress;
        newOrder.status = OrderStatus.Placed;
        newOrder.creationTimestamp = block.timestamp;
        newOrder.lastUpdateTimestamp = block.timestamp;

        uint256 calculatedTotalAmount = 0;
        for (uint i = 0; i < _orderItemsInput.length; i++) {
            OrderItemInput calldata itemInput = _orderItemsInput[i];
            require(itemInput.quantity > 0, "COM: So luong mat hang phai la so duong");

            // THAY ĐỔI:
            (uint256 retailPrice, bool priceExists) = itemsPricingAndListing.getItemRetailPriceAtStore(itemInput.itemId, _storeAddress);
            require(priceExists && retailPrice > 0, "COM: Gia mat hang khong hop le tai cua hang");

            newOrder.items.push(OrderItem({
                itemId: itemInput.itemId,
                quantity: itemInput.quantity,
                unitPrice: retailPrice,
                status: OrderItemStatus.PendingStoreProcessing
            }));
            calculatedTotalAmount += retailPrice * itemInput.quantity;
        }

        require(msg.value == calculatedTotalAmount, "COM: So tien thanh toan khong chinh xac");
        newOrder.totalAmountPaid = calculatedTotalAmount;

        customerOrderIds[msg.sender].push(currentOrderId);
        storeAssignedOrderIds[_storeAddress].push(currentOrderId);

        emit OrderPlaced(currentOrderId, msg.sender, _storeAddress, calculatedTotalAmount);
        emit OrderOverallStatusUpdated(currentOrderId, newOrder.status, block.timestamp);
    }

    function storeUpdateOrderItemStatus(uint256 _orderId, uint256 _itemIndex, OrderItemStatus _newStatus)
        external
        onlyStoreManagerForOrder(_orderId)
        nonReentrant
    {
        Order storage currentOrder = orders[_orderId];
        require(currentOrder.status == OrderStatus.Placed || currentOrder.status == OrderStatus.ProcessingByStore,
                "COM: Trang thai don hang khong cho phep cua hang cap nhat chi tiet");
        require(_itemIndex < currentOrder.items.length, "COM: Chi muc mat hang khong hop le");
        OrderItem storage item = currentOrder.items[_itemIndex];
        require(
            _newStatus == OrderItemStatus.StoreStockAvailable ||
            _newStatus == OrderItemStatus.StoreNeedsRestock ||
            _newStatus == OrderItemStatus.ReadyForDelivery,
            "COM: Trang thai cap nhat cho mat hang khong hop le"
        );
        item.status = _newStatus;
        currentOrder.lastUpdateTimestamp = block.timestamp;
        emit OrderItemStatusUpdatedByStore(_orderId, _itemIndex, item.itemId, _newStatus, msg.sender);
        if (currentOrder.status == OrderStatus.Placed) {
            currentOrder.status = OrderStatus.ProcessingByStore;
            emit OrderOverallStatusUpdated(_orderId, currentOrder.status, block.timestamp);
        }
    }

    function storeConfirmAllItemsReadyForDelivery(uint256 _orderId)
        external
        onlyStoreManagerForOrder(_orderId)
        nonReentrant
    {
        Order storage currentOrder = orders[_orderId];
        require(currentOrder.status == OrderStatus.ProcessingByStore, "COM: Don hang chua o trang thai dang xu ly boi cua hang");
        for (uint i = 0; i < currentOrder.items.length; i++) {
            require(currentOrder.items[i].status == OrderItemStatus.ReadyForDelivery, "COM: Chua du tat ca mat hang trong don san sang de giao");
        }
        currentOrder.status = OrderStatus.AllItemsReadyForDelivery;
        currentOrder.lastUpdateTimestamp = block.timestamp;
        emit OrderReadyForDelivery(_orderId, currentOrder.storeAddress, msg.sender);
        emit OrderOverallStatusUpdated(_orderId, currentOrder.status, block.timestamp);
    }

    function storeConfirmDeliveryToCustomer(uint256 _orderId)
        external
        onlyStoreManagerForOrder(_orderId)
        nonReentrant
    {
        Order storage currentOrder = orders[_orderId];
        require(currentOrder.status == OrderStatus.AllItemsReadyForDelivery, "COM: Don hang chua san sang de giao");
        require(address(storeInventoryManagement) != address(0), "COM: Dia chi SIM chua duoc dat");
        for (uint i = 0; i < currentOrder.items.length; i++) {
            OrderItem storage item = currentOrder.items[i];
            require(item.status == OrderItemStatus.ReadyForDelivery, "COM: Mot mat hang trong don chua san sang de giao");
            storeInventoryManagement.deductStockForCustomerSale(
                currentOrder.storeAddress,
                item.itemId,
                item.quantity,
                _orderId
            );
            item.status = OrderItemStatus.DeliveredToCustomer;
        }
        currentOrder.status = OrderStatus.DeliveryConfirmedByStore;
        currentOrder.lastUpdateTimestamp = block.timestamp;
        emit OrderDeliveryConfirmedByStore(_orderId, currentOrder.storeAddress, msg.sender);
        emit OrderOverallStatusUpdated(_orderId, currentOrder.status, block.timestamp);
    }

    function customerConfirmReceipt(uint256 _orderId)
        external
        onlyOrderCustomer(_orderId)
        nonReentrant
    {
        Order storage currentOrder = orders[_orderId];
        require(currentOrder.status == OrderStatus.DeliveryConfirmedByStore, "COM: Cua hang chua xac nhan giao hang");
        require(!currentOrder.fundsReleasedToCompany, "COM: Tien da duoc giai ngan cho cong ty");
        currentOrder.status = OrderStatus.Completed;
        currentOrder.lastUpdateTimestamp = block.timestamp;
        currentOrder.fundsReleasedToCompany = true;
        (bool success, ) = payable(address(companyTreasuryManager)).call{value: currentOrder.totalAmountPaid}("");
        require(success, "COM: Giai ngan tien cho ngan quy cong ty that bai");
        emit OrderCompletedByCustomer(_orderId, msg.sender);
        emit FundsReleasedToCompanyTreasury(_orderId, currentOrder.totalAmountPaid, address(companyTreasuryManager));
        emit OrderOverallStatusUpdated(_orderId, currentOrder.status, block.timestamp);
    }

    function _internalCancelOrderAndRefundToCustomer(
        uint256 _orderId,
        address _canceller,
        OrderStatus _newStatus,
        string memory _reason,
        uint256 _refundPercentage
    ) internal {
        Order storage currentOrder = orders[_orderId];
        require(!currentOrder.fundsReleasedToCompany, "COM: Khong the huy/hoan tien, tien da chuyen cho cong ty");
        currentOrder.status = _newStatus;
        currentOrder.lastUpdateTimestamp = block.timestamp;
        uint256 amountToRefund = 0;
        if (_refundPercentage > 0 && currentOrder.totalAmountPaid > 0) {
            amountToRefund = (currentOrder.totalAmountPaid * _refundPercentage) / 100;
            if (amountToRefund > 0) {
                (bool success, ) = payable(currentOrder.customerAddress).call{value: amountToRefund}("");
                require(success, "COM: Hoan tien cho khach that bai khi huy don, viec huy bi hoan tac");
            }
        }
        emit OrderCancelled(_orderId, _canceller, _newStatus, _reason, amountToRefund);
        emit OrderOverallStatusUpdated(_orderId, currentOrder.status, block.timestamp);
    }

    function cancelOrderByStore(uint256 _orderId, string calldata _reason)
        external
        onlyStoreManagerForOrder(_orderId)
        nonReentrant
    {
        Order storage currentOrder = orders[_orderId];
        require(currentOrder.status == OrderStatus.Placed || currentOrder.status == OrderStatus.ProcessingByStore,
                "COM: Trang thai don hang khong cho phep cua hang huy");
        _internalCancelOrderAndRefundToCustomer(_orderId, msg.sender, OrderStatus.CancelledByStore, _reason, 100);
    }

    function customerCancelOrderBeforeDelivery(uint256 _orderId, string calldata _reason)
        external
        onlyOrderCustomer(_orderId)
        nonReentrant
    {
        Order storage currentOrder = orders[_orderId];
        require(currentOrder.status < OrderStatus.DeliveryConfirmedByStore &&
                currentOrder.status != OrderStatus.CancelledByStore &&
                currentOrder.status != OrderStatus.CancelledByCustomer,
                "COM: Trang thai don hang khong cho phep khach huy");
        _internalCancelOrderAndRefundToCustomer(_orderId, msg.sender, OrderStatus.CancelledByCustomer, _reason, 100);
    }

    function customerReturnOrderAfterReceipt(uint256 _orderId, address _returnToWarehouseAddress, string calldata _reason)
        external
        onlyOrderCustomer(_orderId)
        nonReentrant
    {
        Order storage currentOrder = orders[_orderId];
        require(currentOrder.status == OrderStatus.Completed, "COM: Don hang chua hoan thanh de co the tra lai");
        require(address(warehouseInventoryManagement) != address(0), "COM: Dia chi WIM cho viec tra hang chua duoc dat");
        require(_returnToWarehouseAddress != address(0), "COM: Dia chi kho tra hang khong hop le");

        for (uint i = 0; i < currentOrder.items.length; i++) {
            OrderItem memory item = currentOrder.items[i];
            warehouseInventoryManagement.recordReturnedStockByCustomer(
                _returnToWarehouseAddress,
                item.itemId,
                item.quantity,
                _orderId
            );
        }
        currentOrder.status = OrderStatus.ReturnedByCustomer;
        currentOrder.lastUpdateTimestamp = block.timestamp;
        uint256 refundPercentage = 90;
        uint256 amountToRefundFromTreasury = (currentOrder.totalAmountPaid * refundPercentage) / 100;
        if (amountToRefundFromTreasury > 0) {
            companyTreasuryManager.refundCustomerOrderFromTreasury(
                _orderId,
                payable(currentOrder.customerAddress),
                amountToRefundFromTreasury
            );
        }
        emit OrderReturnProcessed(_orderId, msg.sender, _returnToWarehouseAddress, _reason);
        emit OrderOverallStatusUpdated(_orderId, currentOrder.status, block.timestamp);
    }

    function getOrderDetails(uint256 _orderId) external view returns (Order memory) {
        require(orders[_orderId].orderId != 0, "COM: Don hang khong ton tai");
        return orders[_orderId];
    }

    function getOrderItems(uint256 _orderId) external view returns (OrderItem[] memory) {
        require(orders[_orderId].orderId != 0, "COM: Don hang khong ton tai");
        return orders[_orderId].items;
    }

    function getCustomerOrders(address _customer) external view returns (uint256[] memory) {
        return customerOrderIds[_customer];
    }

    function getStoreAssignedOrders(address _store) external view returns (uint256[] memory) {
        return storeAssignedOrderIds[_store];
    }

    function emergencyWithdrawEther(address payable _to) external onlyOwner nonReentrant {
        require(_to != address(0), "COM: Nguoi nhan khong hop le");
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = _to.call{value: balance}("");
            require(success, "COM: Rut tien khan cap that bai");
        }
    }
}
