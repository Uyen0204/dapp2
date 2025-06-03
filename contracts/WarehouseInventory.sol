// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interfaces.sol";      // Import file Interfaces.sol tập trung
// KHÔNG CẦN: import "./ItemsManagement.sol";

// Hợp đồng Quản lý Tồn kho Chính (Kho trung tâm)
contract WarehouseInventoryManagement is Ownable {
    // Sử dụng các interface từ Interfaces.sol
    IRoleManagementInterface public roleManagementExternal;
    // THAY ĐỔI:
    IItemsManagementCoreInterface public itemsManagementCore;
    IStoreInventoryManagementInterface public storeInventoryManagementExternal;

    address public warehouseSupplierOrderManagementAddress;
    address public customerOrderManagementAddress;

    mapping(address => mapping(string => uint256)) public stockLevels;
    mapping(address => mapping(string => uint256)) public returnedStockByCustomer;
    uint256 public nextInternalTransferId = 1;

    // --- EVENTS ---
    event StockInFromSupplierRecorded(address indexed warehouseAddress, string itemId, uint256 quantityAdded, uint256 indexed wsOrderId, address indexed byWsom);
    event StockTransferredToStore(address indexed fromWarehouseAddress, address indexed toStoreAddress, string itemId, uint256 quantity, uint256 indexed internalTransferId, address byWarehouseManager);
    event CustomerStockReturnedRecordedToWarehouse(address indexed returnToWarehouseAddress, string itemId, uint256 quantityReturned, uint256 indexed customerOrderId);
    event StockAdjusted(address indexed warehouseAddress, string indexed itemId, int256 quantityChange, string reason, address indexed byAdminOrManager);
    event ProcessedReturnedCustomerStockAtWarehouse(address indexed warehouseAddress, string indexed itemId, uint256 quantityProcessed, bool addedToMainStock, address indexed byAdminOrManager);
    event StoreInventoryManagementAddressSet(address indexed simAddress);
    event WarehouseSupplierOrderManagementAddressSet(address indexed wsomAddress);
    event CustomerOrderManagementAddressSet(address indexed comAddress);

    // --- CONSTRUCTOR ---
    constructor(
        address _roleManagementAddress,
        // THAY ĐỔI:
        address _itemsManagementCoreAddress
    ) Ownable() {
        require(_roleManagementAddress != address(0), "WIM: Dia chi RM khong hop le");
        roleManagementExternal = IRoleManagementInterface(_roleManagementAddress);

        // THAY ĐỔI:
        require(_itemsManagementCoreAddress != address(0), "WIM: Dia chi ItemsMCore khong hop le");
        itemsManagementCore = IItemsManagementCoreInterface(_itemsManagementCoreAddress);
    }

    modifier onlyWarehouseManager(address _warehouseAddress) {
        require(_warehouseAddress != address(0), "WIM: Dia chi kho khong hop le");
        // THAY ĐỔI:
        PhysicalLocationInfo memory whInfo = itemsManagementCore.getWarehouseInfo(_warehouseAddress);
        require(whInfo.exists, "WIM: Kho chua duoc dang ky trong ItemsMCore");
        require(whInfo.manager == msg.sender, "WIM: Nguoi goi khong phai quan ly kho nay");
        bytes32 wmRole = roleManagementExternal.WAREHOUSE_MANAGER_ROLE();
        require(roleManagementExternal.hasRole(wmRole, msg.sender), "WIM: Nguoi goi thieu vai tro QUAN_LY_KHO");
        _;
    }

    function setStoreInventoryManagementAddress(address _simAddress) external onlyOwner {
        require(_simAddress != address(0), "WIM: Dia chi SIM khong hop le");
        storeInventoryManagementExternal = IStoreInventoryManagementInterface(_simAddress);
        emit StoreInventoryManagementAddressSet(_simAddress);
    }

    function setWarehouseSupplierOrderManagementAddress(address _wsomAddress) external onlyOwner {
        require(_wsomAddress != address(0), "WIM: Dia chi WSOM khong hop le");
        warehouseSupplierOrderManagementAddress = _wsomAddress;
        emit WarehouseSupplierOrderManagementAddressSet(_wsomAddress);
    }

    function setCustomerOrderManagementAddress(address _comAddress) external onlyOwner {
        require(_comAddress != address(0), "WIM: Dia chi COM khong hop le");
        customerOrderManagementAddress = _comAddress;
        emit CustomerOrderManagementAddressSet(_comAddress);
    }

    function recordStockInFromSupplier(
        address _warehouseAddress,
        string calldata _itemId,
        uint256 _quantity,
        uint256 _wsOrderId
    ) external {
        require(msg.sender == warehouseSupplierOrderManagementAddress, "WIM: Nguoi goi khong phai WSOM");
        require(_warehouseAddress != address(0), "WIM: Dia chi kho khong hop le");
        require(_quantity > 0, "WIM: So luong them vao phai la so duong");
        // Tùy chọn xác thực _warehouseAddress qua itemsManagementCore.getWarehouseInfo(_warehouseAddress)
        stockLevels[_warehouseAddress][_itemId] += _quantity;
        emit StockInFromSupplierRecorded(_warehouseAddress, _itemId, _quantity, _wsOrderId, msg.sender);
    }

    function requestStockTransferToStore(
        address _requestingStoreManager,
        address _storeAddress,
        address _warehouseAddress,
        string calldata _itemId,
        uint256 _quantity
    ) external returns (uint256 internalTransferId) {
        require(msg.sender == address(storeInventoryManagementExternal), "WIM: Nguoi goi khong phai SIM");
        require(_storeAddress != address(0), "WIM: Dia chi cua hang khong hop le");
        require(_warehouseAddress != address(0), "WIM: Dia chi kho nguon khong hop le");
        require(_quantity > 0, "WIM: So luong chuyen phai la so duong");
        require(address(storeInventoryManagementExternal) != address(0), "WIM: Dia chi SIM chua duoc thiet lap");

        // THAY ĐỔI: (Tùy chọn kiểm tra, vì SIM là người gọi đáng tin cậy)
        // PhysicalLocationInfo memory whInfo = itemsManagementCore.getWarehouseInfo(_warehouseAddress);
        // require(whInfo.exists, "WIM: Kho nguon chua duoc dang ky");

        uint256 currentStock = stockLevels[_warehouseAddress][_itemId];
        require(currentStock >= _quantity, "WIM: Khong du hang trong kho");
        stockLevels[_warehouseAddress][_itemId] = currentStock - _quantity;
        internalTransferId = nextInternalTransferId++;
        storeInventoryManagementExternal.confirmStockReceivedFromWarehouse(
            _storeAddress,
            _itemId,
            _quantity,
            _warehouseAddress,
            internalTransferId
        );
        emit StockTransferredToStore(_warehouseAddress, _storeAddress, _itemId, _quantity, internalTransferId, _requestingStoreManager);
        return internalTransferId;
    }

    function recordReturnedStockByCustomer(
        address _returnToWarehouseAddress,
        string calldata _itemId,
        uint256 _quantity,
        uint256 _customerOrderId
    ) external {
        require(msg.sender == customerOrderManagementAddress, "WIM: Nguoi goi khong phai COM duoc uy quyen");
        require(_returnToWarehouseAddress != address(0), "WIM: Dia chi kho tra hang khong hop le");
        require(_quantity > 0, "WIM: So luong tra ve phai la so duong");
        // Tùy chọn xác thực _returnToWarehouseAddress qua itemsManagementCore.getWarehouseInfo(_returnToWarehouseAddress)
        returnedStockByCustomer[_returnToWarehouseAddress][_itemId] += _quantity;
        emit CustomerStockReturnedRecordedToWarehouse(_returnToWarehouseAddress, _itemId, _quantity, _customerOrderId);
    }

    function adjustStockManually(
        address _warehouseAddress,
        string calldata _itemId,
        int256 _quantityChange,
        string calldata _reason
    ) external {
        bool isOwner = (msg.sender == owner());
        bool isAuthorizedManager = false;
        if (!isOwner) {
            // THAY ĐỔI:
            PhysicalLocationInfo memory whInfo = itemsManagementCore.getWarehouseInfo(_warehouseAddress);
            if (whInfo.exists && whInfo.manager == msg.sender) {
                 bytes32 wmRole = roleManagementExternal.WAREHOUSE_MANAGER_ROLE();
                 if(roleManagementExternal.hasRole(wmRole, msg.sender)){
                    isAuthorizedManager = true;
                 }
            }
        }
        require(isOwner || isAuthorizedManager, "WIM: Khong co quyen dieu chinh ton kho nay");
        uint256 currentStock = stockLevels[_warehouseAddress][_itemId];
        if (_quantityChange > 0) {
            stockLevels[_warehouseAddress][_itemId] = currentStock + uint256(_quantityChange);
        } else if (_quantityChange < 0) {
            uint256 amountToDecrease = uint256(-_quantityChange);
            require(currentStock >= amountToDecrease, "WIM: Dieu chinh thu cong dan den ton kho am");
            stockLevels[_warehouseAddress][_itemId] = currentStock - amountToDecrease;
        } else {
            revert("WIM: Thay doi so luong khong the bang khong");
        }
        emit StockAdjusted(_warehouseAddress, _itemId, _quantityChange, _reason, msg.sender);
    }

    function processCustomerReturnedStock(
        address _warehouseAddress,
        string calldata _itemId,
        uint256 _quantityToProcess,
        bool _addToMainStock
    ) external {
        bool isOwner = (msg.sender == owner());
        bool isAuthorizedManager = false;
        if (!isOwner) {
            // THAY ĐỔI:
            PhysicalLocationInfo memory whInfo = itemsManagementCore.getWarehouseInfo(_warehouseAddress);
            if (whInfo.exists && whInfo.manager == msg.sender) {
                 bytes32 wmRole = roleManagementExternal.WAREHOUSE_MANAGER_ROLE();
                 if(roleManagementExternal.hasRole(wmRole, msg.sender)){
                    isAuthorizedManager = true;
                 }
            }
        }
        require(isOwner || isAuthorizedManager, "WIM: Khong co quyen xu ly hang tra ve kho nay");
        require(_quantityToProcess > 0, "WIM: So luong xu ly phai la so duong");
        uint256 currentReturnedStock = returnedStockByCustomer[_warehouseAddress][_itemId];
        require(currentReturnedStock >= _quantityToProcess, "WIM: Khong du hang tra ve de xu ly");
        returnedStockByCustomer[_warehouseAddress][_itemId] = currentReturnedStock - _quantityToProcess;
        if (_addToMainStock) {
            stockLevels[_warehouseAddress][_itemId] += _quantityToProcess;
        }
        emit ProcessedReturnedCustomerStockAtWarehouse(_warehouseAddress, _itemId, _quantityToProcess, _addToMainStock, msg.sender);
    }

    function getWarehouseStockLevel(address _warehouseAddress, string calldata _itemId) external view returns (uint256) {
        require(_warehouseAddress != address(0), "WIM: Dia chi kho khong hop le");
        return stockLevels[_warehouseAddress][_itemId];
    }

    function getCustomerReturnedStockLevelAtWarehouse(address _warehouseAddress, string calldata _itemId) external view returns (uint256) {
        require(_warehouseAddress != address(0), "WIM: Dia chi kho khong hop le");
        return returnedStockByCustomer[_warehouseAddress][_itemId];
    }
}