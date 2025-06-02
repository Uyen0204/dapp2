// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./Interfaces.sol"; // Import file Interfaces.sol tập trung

contract ItemsManagementCore is AccessControl, IItemsManagementCoreInterface {
    IRoleManagement public roleManagementExternal;

    // --- STRUCT DEFINITIONS ---
    // ItemInfo, PhysicalLocationInfo, SupplierInfo được định nghĩa trong Interfaces.sol
    // và được contract này sử dụng/triển khai.

    // --- MAPPINGS ---
    mapping(string => ItemInfo) public override items;
    mapping(address => PhysicalLocationInfo) public override physicalLocations;
    mapping(address => SupplierInfo) public override suppliers;

    // --- ARRAYS FOR ITERATION ---
    string[] public override itemIds;
    address[] public override locationAddresses;
    address[] public override supplierAddresses;

    // --- EVENTS (chỉ những event liên quan đến core entities) ---
    event ItemProposed(string indexed itemId, string name, address indexed proposer);
    event ItemApprovedByBoard(string indexed itemId, uint256 referencePriceCeiling, address indexed finalApprover);
    event PhysicalLocationProposed(address indexed locationId, string name, string locationType, address indexed proposer);
    event PhysicalLocationApprovedByBoard(address indexed locationId, address indexed finalApprover);
    event SupplierProposed(address indexed supplierId, string name, address indexed proposer);
    event SupplierApprovedByBoard(address indexed supplierId, address indexed finalApprover);
    event PhysicalLocationManagerAssigned(address indexed locationId, address newManager, address indexed byDirector);
    event StoreDesignatedSourceWarehouseSet(address indexed storeAddress, address indexed designatedWarehouse, address indexed byStoreDirector);

    constructor(address _roleManagementExternalAddress) {
        require(_roleManagementExternalAddress != address(0), "ItemsMCore: Dia chi RM Ngoai khong hop le");
        roleManagementExternal = IRoleManagement(_roleManagementExternalAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyBoardMember() {
        require(roleManagementExternal.hasRole(roleManagementExternal.BOARD_ROLE(), msg.sender), "ItemsMCore: Nguoi goi khong phai Thanh vien BDH");
        _;
    }

    modifier onlyStoreDirector() {
        bytes32 sdRole = roleManagementExternal.STORE_DIRECTOR_ROLE();
        require(roleManagementExternal.hasRole(sdRole, msg.sender), "ItemsMCore: Nguoi goi thieu vai tro GIAM_DOC_CH (RM Ngoai)");
        _;
    }

    modifier onlyWarehouseDirector() { // Thêm modifier này nếu chưa có
        bytes32 wdRole = roleManagementExternal.WAREHOUSE_DIRECTOR_ROLE();
        require(roleManagementExternal.hasRole(wdRole, msg.sender), "ItemsMCore: Nguoi goi thieu vai tro GIAM_DOC_KHO (RM Ngoai)");
        _;
    }

    function _getBoardApproval(address[] memory _approvers) internal view returns (bool) {
        if (_approvers.length == 0) return false;
        uint256 totalApprovalShares = 0;
        address[] memory processedApprovers = new address[](_approvers.length);
        uint processedCount = 0;

        for (uint i = 0; i < _approvers.length; i++) {
            address approver = _approvers[i];
            require(approver != msg.sender, "ItemsMCore: Nguoi de xuat khong the tu phe duyet");
            require(roleManagementExternal.hasRole(roleManagementExternal.BOARD_ROLE(), approver), "ItemsMCore: Nguoi phe duyet khong phai thanh vien BDH");

            bool alreadyProcessed = false;
            for (uint j = 0; j < processedCount; j++) {
                if (processedApprovers[j] == approver) {
                    alreadyProcessed = true;
                    break;
                }
            }
            require(!alreadyProcessed, "ItemsMCore: Nguoi phe duyet bi trung lap");
            totalApprovalShares += roleManagementExternal.getSharesPercentage(approver);
            processedApprovers[processedCount] = approver;
            processedCount++;
        }
        return totalApprovalShares > 5000; // 5000 means > 50.00%
    }

    function _itemExistsInArray(string calldata _itemId) internal view returns (bool) {
        for (uint i = 0; i < itemIds.length; i++) {
            if (keccak256(abi.encodePacked(itemIds[i])) == keccak256(abi.encodePacked(_itemId))) return true;
        }
        return false;
    }
    function _locationExistsInArray(address _locationId) internal view returns (bool) {
        for (uint i = 0; i < locationAddresses.length; i++) {
            if (locationAddresses[i] == _locationId) return true;
        }
        return false;
    }
     function _supplierExistsInArray(address _supplierId) internal view returns (bool) {
        for (uint i = 0; i < supplierAddresses.length; i++) {
            if (supplierAddresses[i] == _supplierId) return true;
        }
        return false;
    }

    // --- QUẢN LÝ MẶT HÀNG BỞI BAN ĐIỀU HÀNH ---
    function proposeNewItem(string calldata _itemId, string calldata _name, string calldata _description, string calldata _category) external override onlyBoardMember {
        require(!items[_itemId].exists, "ItemsMCore: ID mat hang da ton tai");
        require(bytes(_itemId).length > 0, "ItemsMCore: ID mat hang khong duoc rong");

        items[_itemId] = ItemInfo({
            itemId: _itemId,
            name: _name,
            description: _description,
            category: _category,
            exists: true,
            isApprovedByBoard: false,
            proposer: msg.sender,
            referencePriceCeiling: 0
        });
        if (!_itemExistsInArray(_itemId)) {
            itemIds.push(_itemId);
        }
        emit ItemProposed(_itemId, _name, msg.sender);
    }

    function approveProposedItem(string calldata _itemId, uint256 _referencePriceCeiling, address[] calldata _approvers) external override onlyBoardMember {
        ItemInfo storage item = items[_itemId];
        require(item.exists, "ItemsMCore: Mat hang khong ton tai de phe duyet");
        require(!item.isApprovedByBoard, "ItemsMCore: Mat hang da duoc phe duyet roi");
        require(_referencePriceCeiling > 0, "ItemsMCore: Gia tran tham khao phai lon hon 0");
        require(_getBoardApproval(_approvers), "ItemsMCore: Khong du ty le co phan BDH phe duyet");

        item.isApprovedByBoard = true;
        item.referencePriceCeiling = _referencePriceCeiling;
        emit ItemApprovedByBoard(_itemId, _referencePriceCeiling, msg.sender);
    }

    // --- QUẢN LÝ ĐỊA ĐIỂM BỞI BAN ĐIỀU HÀNH ---
    function proposeNewPhysicalLocation(address _locationId, string calldata _name, string calldata _locationType) external override onlyBoardMember {
        require(!physicalLocations[_locationId].exists, "ItemsMCore: ID dia diem da ton tai");
        require(_locationId != address(0), "ItemsMCore: Dia chi dia diem khong hop le");
        bytes32 typeHash = keccak256(abi.encodePacked(_locationType));
        require(typeHash == keccak256(abi.encodePacked("STORE")) || typeHash == keccak256(abi.encodePacked("WAREHOUSE")), "ItemsMCore: Loai dia diem khong hop le");

        physicalLocations[_locationId] = PhysicalLocationInfo({
            locationId: _locationId,
            name: _name,
            locationType: _locationType,
            manager: address(0),
            exists: true,
            isApprovedByBoard: false,
            designatedSourceWarehouseAddress: address(0)
        });
        if (!_locationExistsInArray(_locationId)) {
            locationAddresses.push(_locationId);
        }
        emit PhysicalLocationProposed(_locationId, _name, _locationType, msg.sender);
    }

    function approveProposedPhysicalLocation(address _locationId, address[] calldata _approvers) external override onlyBoardMember {
        PhysicalLocationInfo storage loc = physicalLocations[_locationId];
        require(loc.exists, "ItemsMCore: Dia diem khong ton tai de phe duyet");
        require(!loc.isApprovedByBoard, "ItemsMCore: Dia diem da duoc phe duyet roi");
        require(_getBoardApproval(_approvers), "ItemsMCore: Khong du ty le co phan BDH phe duyet");

        loc.isApprovedByBoard = true;
        emit PhysicalLocationApprovedByBoard(_locationId, msg.sender);
    }

    function assignManagerToLocation(address _locationId, address _managerId) external override {
        PhysicalLocationInfo storage loc = physicalLocations[_locationId];
        require(loc.exists && loc.isApprovedByBoard, "ItemsMCore: Dia diem chua ton tai hoac chua duoc BDH phe duyet");
        require(loc.manager == address(0), "ItemsMCore: Dia diem da co quan ly");

        bytes32 expectedManagerRole;
        bool callerIsAuthorized = false;

        if (keccak256(abi.encodePacked(loc.locationType)) == keccak256(abi.encodePacked("STORE"))) {
            expectedManagerRole = roleManagementExternal.STORE_MANAGER_ROLE();
            if (roleManagementExternal.hasRole(roleManagementExternal.STORE_DIRECTOR_ROLE(), msg.sender)) {
                callerIsAuthorized = true;
            }
        } else if (keccak256(abi.encodePacked(loc.locationType)) == keccak256(abi.encodePacked("WAREHOUSE"))) {
            expectedManagerRole = roleManagementExternal.WAREHOUSE_MANAGER_ROLE();
            if (roleManagementExternal.hasRole(roleManagementExternal.WAREHOUSE_DIRECTOR_ROLE(), msg.sender)) {
                callerIsAuthorized = true;
            }
        } else {
            revert("ItemsMCore: Loai dia diem khong xac dinh de gan quan ly");
        }
        require(callerIsAuthorized, "ItemsMCore: Nguoi goi khong co quyen gan quan ly cho loai dia diem nay");
        require(roleManagementExternal.hasRole(expectedManagerRole, _managerId), "ItemsMCore: Nguoi duoc gan lam quan ly thieu vai tro phu hop");
        loc.manager = _managerId;
        emit PhysicalLocationManagerAssigned(_locationId, _managerId, msg.sender);
    }

    function setDesignatedSourceWarehouseForStore(address _storeAddress, address _warehouseAddress) external override onlyStoreDirector {
        PhysicalLocationInfo storage storeInfo = physicalLocations[_storeAddress];
        require(storeInfo.exists && storeInfo.isApprovedByBoard && keccak256(abi.encodePacked(storeInfo.locationType)) == keccak256(abi.encodePacked("STORE")), "ItemsMCore: Cua hang khong ton tai, chua duoc BDH phe duyet, hoac khong phai la cua hang");
        if (_warehouseAddress != address(0)) {
            PhysicalLocationInfo memory warehouseInfo = physicalLocations[_warehouseAddress];
            require(warehouseInfo.exists && warehouseInfo.isApprovedByBoard && keccak256(abi.encodePacked(warehouseInfo.locationType)) == keccak256(abi.encodePacked("WAREHOUSE")), "ItemsMCore: Kho nguon chi dinh khong hop le, chua duoc BDH phe duyet, hoac khong phai la kho");
        }
        storeInfo.designatedSourceWarehouseAddress = _warehouseAddress;
        emit StoreDesignatedSourceWarehouseSet(_storeAddress, _warehouseAddress, msg.sender);
    }

    // --- QUẢN LÝ NHÀ CUNG CẤP BỞI BAN ĐIỀU HÀNH ---
    function proposeNewSupplier(address _supplierId, string calldata _name) external override onlyBoardMember {
        require(!suppliers[_supplierId].exists, "ItemsMCore: ID NCC da ton tai");
        require(_supplierId != address(0), "ItemsMCore: Dia chi NCC khong hop le");
        require(roleManagementExternal.hasRole(roleManagementExternal.SUPPLIER_ROLE(), _supplierId), "ItemsMCore: NCC de xuat thieu vai tro NCC tu RM");

        suppliers[_supplierId] = SupplierInfo({
            supplierId: _supplierId,
            name: _name,
            isApprovedByBoard: false,
            exists: true
        });
        if(!_supplierExistsInArray(_supplierId)){
             supplierAddresses.push(_supplierId);
        }
        emit SupplierProposed(_supplierId, _name, msg.sender);
    }

    function approveProposedSupplier(address _supplierId, address[] calldata _approvers) external override onlyBoardMember {
        SupplierInfo storage sup = suppliers[_supplierId];
        require(sup.exists, "ItemsMCore: NCC khong ton tai de phe duyet");
        require(!sup.isApprovedByBoard, "ItemsMCore: NCC da duoc phe duyet roi");
        require(_getBoardApproval(_approvers), "ItemsMCore: Khong du ty le co phan BDH phe duyet");
        sup.isApprovedByBoard = true;
        emit SupplierApprovedByBoard(_supplierId, msg.sender);
    }

    // --- VIEW FUNCTIONS (implementing IItemsManagementCoreInterface) ---
    function getItemInfo(string calldata _itemId) external view override returns (ItemInfo memory) {
        return items[_itemId];
    }
    function getPhysicalLocationInfo(address _locationId) external view override returns (PhysicalLocationInfo memory) {
        return physicalLocations[_locationId];
    }
    function getStoreInfo(address _storeAddress) external view override returns (PhysicalLocationInfo memory) {
        PhysicalLocationInfo memory loc = physicalLocations[_storeAddress];
        require(loc.exists && keccak256(abi.encodePacked(loc.locationType)) == keccak256(abi.encodePacked("STORE")), "ItemsMCore: Khong phai la cua hang");
        return loc;
    }
    function getWarehouseInfo(address _warehouseAddress) external view override returns (PhysicalLocationInfo memory) {
        PhysicalLocationInfo memory loc = physicalLocations[_warehouseAddress];
        require(loc.exists && keccak256(abi.encodePacked(loc.locationType)) == keccak256(abi.encodePacked("WAREHOUSE")), "ItemsMCore: Khong phai la kho");
        return loc;
    }
    function getSupplierInfo(address _supplierId) external view override returns (SupplierInfo memory) {
        return suppliers[_supplierId];
    }
    function getAllItemIds() external view override returns (string[] memory) { return itemIds; }
    function getAllLocationAddresses() external view override returns (address[] memory) { return locationAddresses; }
    function getAllSupplierAddresses() external view override returns (address[] memory) { return supplierAddresses; }
}
