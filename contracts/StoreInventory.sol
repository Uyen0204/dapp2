// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interfaces.sol";      // Import file Interfaces.sol tập trung
import "./ItemsManagement.sol"; // Import ItemsManagement để trình biên dịch liên kết contract

// Hợp đồng Quản lý Tồn kho Cửa hàng
contract StoreInventoryManagement is Ownable {
    // Sử dụng các interface từ Interfaces.sol
    IRoleManagementInterface public roleManagementExternal;
    IItemsManagementInterface public itemsManagementExternal;
    IWarehouseInventoryManagementInterface public warehouseInventoryManagementExternal;

    address public customerOrderManagementAddress; // Để xác thực người gọi deductStockForCustomerSale

    // Tồn kho cửa hàng: storeAddress => itemId => quantity
    mapping(address => mapping(string => uint256)) public storeStockLevels;

    // Không còn theo dõi pendingTransfers trực tiếp ở đây, WIM sẽ gọi lại confirmStockReceivedFromWarehouse

    // --- EVENTS ---
    event StockRequestedFromWarehouse(
        address indexed storeAddress,
        address indexed designatedWarehouse,
        string itemId, // Thường không cần indexed nếu bạn đã có storeAddress và designatedWarehouse
        uint256 quantity,
        uint256 indexed wimTransferId, // ID từ WIM để theo dõi
        address byStoreManager
    );
    event StockReceivedAtStore(
        address indexed storeAddress,
        string indexed itemId, // itemId ở đây có thể hữu ích để theo dõi mặt hàng nào được nhận
        uint256 quantity,
        address indexed fromWarehouse,
        uint256 wimTransferId // ID từ WIM để đối chiếu
    );
    event StockDeductedForSale(
        address indexed storeAddress,
        string indexed itemId, // Tương tự, itemId ở đây có thể hữu ích
        uint256 quantityDeducted,
        uint256 indexed customerOrderId
    );
    event StoreStockAdjusted(
        address indexed storeAddress,
        string indexed itemId,
        int256 quantityChange,
        string reason,
        address indexed byAdminOrManager // Phản ánh ai đã thực hiện
    );

    // Admin/Owner events
    event WarehouseInventoryManagementAddressSet(address indexed wimAddress);
    event CustomerOrderManagementAddressSet(address indexed comAddress);


    // --- CONSTRUCTOR ---
    constructor(address _roleManagementAddress, address _itemsManagementAddress) Ownable() {
        require(_roleManagementAddress != address(0), "SIM: Dia chi RM khong hop le");
        roleManagementExternal = IRoleManagementInterface(_roleManagementAddress);

        require(_itemsManagementAddress != address(0), "SIM: Dia chi ItemsM khong hop le");
        itemsManagementExternal = IItemsManagementInterface(_itemsManagementAddress);
    }

    // --- MODIFIERS ---
    // Modifier chỉ cho phép Quản lý Cửa hàng của cửa hàng được chỉ định
    modifier onlyStoreManager(address _storeAddress) {
        require(_storeAddress != address(0), "SIM: Dia chi cua hang khong hop le");
        // Sử dụng PhysicalLocationInfo đã được forward-declare trong Interfaces.sol
        PhysicalLocationInfo memory storeInfo = itemsManagementExternal.getStoreInfo(_storeAddress);
        require(storeInfo.exists, "SIM: Cua hang chua duoc dang ky trong ItemsM");
        require(storeInfo.manager == msg.sender, "SIM: Nguoi goi khong phai quan ly cua hang nay");

        bytes32 smRole = roleManagementExternal.STORE_MANAGER_ROLE();
        require(roleManagementExternal.hasRole(smRole, msg.sender), "SIM: Nguoi goi thieu vai tro QUAN_LY_CH");
        _;
    }

    // --- HÀM SETTER (Chỉ Owner) ---
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

    // --- CÁC HÀM CỐT LÕI ---

    // Được gọi bởi Quản lý Cửa hàng để lấy hàng từ kho nguồn chỉ định của họ
    function requestStockFromDesignatedWarehouse(
        address _storeAddress, // Cửa hàng yêu cầu (msg.sender phải là quản lý của cửa hàng này)
        string calldata _itemId,
        uint256 _quantity
    ) external onlyStoreManager(_storeAddress) { // Modifier đảm bảo msg.sender là quản lý của _storeAddress
        require(address(warehouseInventoryManagementExternal) != address(0), "SIM: Dia chi WIM chua duoc dat");
        require(_quantity > 0, "SIM: So luong phai la so duong");

        // itemsManagementExternal.getStoreInfo đã được gọi trong modifier
        PhysicalLocationInfo memory storeInfo = itemsManagementExternal.getStoreInfo(_storeAddress);
        require(storeInfo.designatedSourceWarehouseAddress != address(0), "SIM: Cua hang khong co kho nguon chi dinh");

        uint256 wimTransferId = warehouseInventoryManagementExternal.requestStockTransferToStore(
            msg.sender, // Quản lý cửa hàng đang yêu cầu
            _storeAddress,
            storeInfo.designatedSourceWarehouseAddress,
            _itemId,
            _quantity
        );

        emit StockRequestedFromWarehouse(_storeAddress, storeInfo.designatedSourceWarehouseAddress, _itemId, _quantity, wimTransferId, msg.sender);
    }

    // Được gọi bởi WarehouseInventoryManagement sau khi đã xử lý việc chuyển hàng
    function confirmStockReceivedFromWarehouse(
        address _storeAddress,
        string calldata _itemId,
        uint256 _quantity,
        address _fromWarehouseAddress, // Kho đã gửi hàng
        uint256 _internalTransferId    // ID giao dịch chuyển nội bộ từ WIM để đối chiếu
    ) external {
        require(msg.sender == address(warehouseInventoryManagementExternal), "SIM: Nguoi goi khong phai WIM");
        require(_storeAddress != address(0), "SIM: Dia chi cua hang khong hop le");
        require(_fromWarehouseAddress != address(0), "SIM: Dia chi kho gui khong hop le");
        require(_quantity > 0, "SIM: So luong nhan phai duong");

        // Tùy chọn: Xác thực _storeAddress tồn tại thông qua itemsManagementExternal
        // PhysicalLocationInfo memory storeInfo = itemsManagementExternal.getStoreInfo(_storeAddress);
        // require(storeInfo.exists, "SIM: Cua hang nhan khong ton tai");

        storeStockLevels[_storeAddress][_itemId] += _quantity;
        emit StockReceivedAtStore(_storeAddress, _itemId, _quantity, _fromWarehouseAddress, _internalTransferId);
    }

    // Được gọi bởi CustomerOrderManagement khi một đơn hàng được hoàn thành và cần trừ tồn kho
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

    // --- CÁC HÀM ADMIN/QUẢN LÝ CỬA HÀNG ---
    function adjustStoreStockManually(
        address _storeAddress,
        string calldata _itemId,
        int256 _quantityChange,
        string calldata _reason
    ) external { // Cho phép Owner hoặc Quản lý cửa hàng đó
        bool isOwner = (msg.sender == owner());
        bool isAuthorizedManager = false;
        if (!isOwner) {
            // Kiểm tra xem msg.sender có phải là quản lý của _storeAddress không
            // và có vai trò STORE_MANAGER_ROLE không
            PhysicalLocationInfo memory storeInfo = itemsManagementExternal.getStoreInfo(_storeAddress);
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

    // --- CÁC HÀM XEM (VIEW FUNCTIONS) ---
    function getStoreStockLevel(address _storeAddress, string calldata _itemId) external view returns (uint256) {
        require(_storeAddress != address(0), "SIM: Dia chi cua hang khong hop le");
        return storeStockLevels[_storeAddress][_itemId];
    }
}