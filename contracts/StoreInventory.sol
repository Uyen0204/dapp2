// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interfaces.sol";      // Import file Interfaces.sol tập trung
// KHÔNG CẦN: import "./ItemsManagement.sol";

// Hợp đồng Quản lý Tồn kho Cửa hàng
contract StoreInventoryManagement is Ownable {
    // Sử dụng các interface từ Interfaces.sol
    IRoleManagementInterface public roleManagementExternal;
    // THAY ĐỔI:
    IItemsManagementCoreInterface public itemsManagementCore;
    IWarehouseInventoryManagementInterface public warehouseInventoryManagementExternal;

    address public customerOrderManagementAddress;

    mapping(address => mapping(string => uint256)) public storeStockLevels;

    // --- EVENTS ---
    event StockRequestedFromWarehouse(
        address indexed storeAddress,
        address indexed designatedWarehouse,
        string itemId,
        uint256 quantity,
        uint256 indexed wimTransferId,
        address byStoreManager
    );
    event StockReceivedAtStore(
        address indexed storeAddress,
        string indexed itemId,
        uint256 quantity,
        address indexed fromWarehouse,
        uint256 wimTransferId
    );
    event StockDeductedForSale(
        address indexed storeAddress,
        string indexed itemId,
        uint256 quantityDeducted,
        uint256 indexed customerOrderId
    );
    event StoreStockAdjusted(
        address indexed storeAddress,
        string indexed itemId,
        int256 quantityChange,
        string reason,
        address indexed byAdminOrManager
    );
    event WarehouseInventoryManagementAddressSet(address indexed wimAddress);
    event CustomerOrderManagementAddressSet(address indexed comAddress);

    // --- CONSTRUCTOR ---
    constructor(
        address _roleManagementAddress,
        // THAY ĐỔI:
        address _itemsManagementCoreAddress
    ) Ownable() {
        require(_roleManagementAddress != address(0), "SIM: Dia chi RM khong hop le");
        roleManagementExternal = IRoleManagementInterface(_roleManagementAddress);

        // THAY ĐỔI:
        require(_itemsManagementCoreAddress != address(0), "SIM: Dia chi ItemsMCore khong hop le");
        itemsManagementCore = IItemsManagementCoreInterface(_itemsManagementCoreAddress);
    }

    modifier onlyStoreManager(address _storeAddress) {
        require(_storeAddress != address(0), "SIM: Dia chi cua hang khong hop le");
        // THAY ĐỔI:
        PhysicalLocationInfo memory storeInfo = itemsManagementCore.getStoreInfo(_storeAddress);
        require(storeInfo.exists, "SIM: Cua hang chua duoc dang ky trong ItemsMCore");
        require(storeInfo.manager == msg.sender, "SIM: Nguoi goi khong phai quan ly cua hang nay");

        bytes32 smRole = roleManagementExternal.STORE_MANAGER_ROLE();
        require(roleManagementExternal.hasRole(smRole, msg.sender), "SIM: Nguoi goi thieu vai tro QUAN_LY_CH");
        _;
    }

    function setWarehouseInventoryManagementAddress(address _wimAddress) external onlyOwner {
        require(_wimAddress != address(0), "SIM: Dia chi WIM khong hop le");
        warehouseInventoryManagementExternal = IWarehouseInventoryManagementInterface(_wimAddress);
        emit WarehouseInventoryManagementAddressSet(_wimAddress);
    }

    function setCustomerOrderManagementAddress(address _comAddress) external onlyOwner {
        require(_comAddress != address(0), "SIM: Dia chi COM khong hop le");
        customerOrderManagementAddress = _comAddress;
        emit CustomerOrderManagementAddressSet(_comAddress);
    }

    function requestStockFromDesignatedWarehouse(
        address _storeAddress,
        string calldata _itemId,
        uint256 _quantity
    ) external onlyStoreManager(_storeAddress) {
        require(address(warehouseInventoryManagementExternal) != address(0), "SIM: Dia chi WIM chua duoc dat");
        require(_quantity > 0, "SIM: So luong phai la so duong");

        // THAY ĐỔI:
        PhysicalLocationInfo memory storeInfo = itemsManagementCore.getStoreInfo(_storeAddress);
        require(storeInfo.designatedSourceWarehouseAddress != address(0), "SIM: Cua hang khong co kho nguon chi dinh");

        uint256 wimTransferId = warehouseInventoryManagementExternal.requestStockTransferToStore(
            msg.sender,
            _storeAddress,
            storeInfo.designatedSourceWarehouseAddress,
            _itemId,
            _quantity
        );
        emit StockRequestedFromWarehouse(_storeAddress, storeInfo.designatedSourceWarehouseAddress, _itemId, _quantity, wimTransferId, msg.sender);
    }

    function confirmStockReceivedFromWarehouse(
        address _storeAddress,
        string calldata _itemId,
        uint256 _quantity,
        address _fromWarehouseAddress,
        uint256 _internalTransferId
    ) external {
        require(msg.sender == address(warehouseInventoryManagementExternal), "SIM: Nguoi goi khong phai WIM");
        require(_storeAddress != address(0), "SIM: Dia chi cua hang khong hop le");
        require(_fromWarehouseAddress != address(0), "SIM: Dia chi kho gui khong hop le");
        require(_quantity > 0, "SIM: So luong nhan phai duong");
        storeStockLevels[_storeAddress][_itemId] += _quantity;
        emit StockReceivedAtStore(_storeAddress, _itemId, _quantity, _fromWarehouseAddress, _internalTransferId);
    }

    function deductStockForCustomerSale(
        address _storeAddress,
        string calldata _itemId,
        uint256 _quantity,
        uint256 _customerOrderId
    ) external {
        require(msg.sender == customerOrderManagementAddress, "SIM: Nguoi goi khong phai COM");
        require(_storeAddress != address(0), "SIM: Dia chi cua hang khong hop le");
        require(_quantity > 0, "SIM: So luong tru phai la so duong");
        uint256 currentStock = storeStockLevels[_storeAddress][_itemId];
        require(currentStock >= _quantity, "SIM: Khong du ton kho cua hang de ban");
        storeStockLevels[_storeAddress][_itemId] = currentStock - _quantity;
        emit StockDeductedForSale(_storeAddress, _itemId, _quantity, _customerOrderId);
    }

    function adjustStoreStockManually(
        address _storeAddress,
        string calldata _itemId,
        int256 _quantityChange,
        string calldata _reason
    ) external {
        bool isOwner = (msg.sender == owner());
        bool isAuthorizedManager = false;
        if (!isOwner) {
            // THAY ĐỔI:
            PhysicalLocationInfo memory storeInfo = itemsManagementCore.getStoreInfo(_storeAddress);
            if (storeInfo.exists && storeInfo.manager == msg.sender) {
                bytes32 smRole = roleManagementExternal.STORE_MANAGER_ROLE();
                if (roleManagementExternal.hasRole(smRole, msg.sender)) {
                    isAuthorizedManager = true;
                }
            }
        }
        require(isOwner || isAuthorizedManager, "SIM: Khong co quyen dieu chinh ton kho cua hang nay");
        uint256 currentStock = storeStockLevels[_storeAddress][_itemId];
        if (_quantityChange > 0) {
            storeStockLevels[_storeAddress][_itemId] = currentStock + uint256(_quantityChange);
        } else if (_quantityChange < 0) {
            uint256 amountToDecrease = uint256(-_quantityChange);
            require(currentStock >= amountToDecrease, "SIM: Dieu chinh thu cong dan den ton kho am");
            storeStockLevels[_storeAddress][_itemId] = currentStock - amountToDecrease;
        } else {
            revert("SIM: Thay doi so luong khong the bang khong");
        }
        emit StoreStockAdjusted(_storeAddress, _itemId, _quantityChange, _reason, msg.sender);
    }

    function getStoreStockLevel(address _storeAddress, string calldata _itemId) external view returns (uint256) {
        require(_storeAddress != address(0), "SIM: Dia chi cua hang khong hop le");
        return storeStockLevels[_storeAddress][_itemId];
    }
}
