// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4; // Nâng lên để dùng Custom Errors, nếu không thể, hạ xuống và sửa revert

import "@openzeppelin/contracts/access/AccessControl.sol";

// Interface IRoleManagementInterface giữ nguyên
interface IRoleManagementInterface {
    function STORE_DIRECTOR_ROLE() external view returns (bytes32);
    function WAREHOUSE_DIRECTOR_ROLE() external view returns (bytes32);
    function STORE_MANAGER_ROLE() external view returns (bytes32);
    function WAREHOUSE_MANAGER_ROLE() external view returns (bytes32);
    function BOARD_ROLE() external view returns (bytes32);
    function SUPPLIER_ROLE() external view returns (bytes32);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function getSharesPercentage(address account) external view returns (uint256);
}

// --- Custom Errors ---
error IM_InvalidRMAddr();
error IM_NotBoard();
error IM_NotSuppl();
error IM_SupplNotApprv();
error IM_NotStoreDir();
error IM_NotWhDir();
error IM_NotStoreMgr();
error IM_StoreNotValid();
error IM_SelfApprove();
error IM_ApproverNotBoard();
error IM_DupApprover();
error IM_BoardReject();
error IM_ItemExists();
error IM_EmptyItemId();
error IM_ItemNotFound();
error IM_ItemApproved();
error IM_InvalidRefPrice();
error IM_LocExists();
error IM_InvalidLocAddr();
error IM_InvalidLocType();
error IM_LocNotFound();
error IM_LocApproved();
error IM_MgrExists();
error IM_LocNotValidApprv();
error IM_UnknownLocType();
error IM_CallerNotAuth();
error IM_MgrInvalidRole();
error IM_StoreNotValidApprv();
error IM_WhNotValidApprv();
error IM_SupplExists();
error IM_InvalidSupplAddr();
error IM_SupplNotFound();
error IM_SupplApproved();
error IM_ItemNotGlobApproved();
error IM_SupplItemListed();
error IM_InvalidPrice();
error IM_SupplItemNotListed();
error IM_SupplItemApproved();
error IM_InvalidRetailPrice();

contract ItemsManagement is AccessControl {
    IRoleManagementInterface public roleManagementExternal;

    struct ItemInfo {
        string itemId;
        string name; // Giữ lại name vì quan trọng
        // string description; // Bỏ để giảm kích thước
        // string category;    // Bỏ để giảm kích thước
        bool exists;
        bool isApprovedByBoard;
        address proposer;
        uint128 referencePriceCeiling; // Sử dụng uint128
    }

    struct PhysicalLocationInfo {
        address locationId;
        string name; // Giữ lại name
        string locationType; // Cân nhắc dùng enum { STORE, WAREHOUSE }
        address manager;
        bool exists;
        bool isApprovedByBoard;
        address designatedSourceWarehouseAddress;
    }

    struct SupplierInfo {
        address supplierId;
        string name; // Giữ lại name
        bool isApprovedByBoard;
        bool exists;
    }

    struct SupplierItemListing {
        string itemId;
        // address supplierAddress; // Có thể bỏ, dùng msg.sender khi list và mapping key
        uint128 price; // Sử dụng uint128
        bool isApprovedByBoard;
        bool exists;
    }

    mapping(string => ItemInfo) public items;
    mapping(address => PhysicalLocationInfo) public physicalLocations;
    mapping(address => SupplierInfo) public suppliers;
    // Key cho supplierItemListings có thể là keccak256(abi.encodePacked(supplierAddress, itemId))
    // để không cần lưu supplierAddress trong struct SupplierItemListing
    mapping(bytes32 => SupplierItemListing) public supplierItemListings; // Khóa = keccak256(supplierAddress, itemId)
    mapping(address => mapping(string => uint128)) public storeItemRetailPrices; // Sử dụng uint128

    // CÂN NHẮC BỎ CÁC MẢNG NÀY VÀ HÀM GETALL NẾU KÍCH THƯỚC LÀ VẤN ĐỀ LỚN
    // Frontend sẽ cần query events để lấy danh sách.
    /*
    string[] public itemIds;
    address[] public locationAddresses;
    address[] public supplierAddresses;
    */

    // Events (giữ nguyên, đảm bảo không quá 3 indexed per event)
    event ItemProposed(string indexed itemId, string name, address indexed proposer);
    event ItemApprovedByBoard(string indexed itemId, uint128 referencePriceCeiling, address indexed finalApprover);
    event PhysicalLocationProposed(address indexed locationId, string name, string locationType, address indexed proposer);
    event PhysicalLocationApprovedByBoard(address indexed locationId, address indexed finalApprover);
    event SupplierProposed(address indexed supplierId, string name, address indexed proposer);
    event SupplierApprovedByBoard(address indexed supplierId, address indexed finalApprover);
    event PhysicalLocationManagerAssigned(address indexed locationId, address newManager, address indexed byDirector);
    event StoreDesignatedSourceWarehouseSet(address indexed storeAddress, address indexed designatedWarehouse, address indexed byStoreDirector);
    event SupplierItemListed(address indexed supplierAddress, string indexed itemId, uint128 price, bool autoApproved);
    event SupplierItemManuallyApprovedByBoard(address indexed supplierAddress, string indexed itemId, address indexed approver);
    event RetailPriceSet(address indexed storeAddress, string indexed itemId, uint128 price, address indexed byStoreDirector);


    constructor(address _roleManagementExternalAddress) {
        if (_roleManagementExternalAddress == address(0)) revert IM_InvalidRMAddr();
        roleManagementExternal = IRoleManagementInterface(_roleManagementExternalAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender); // Sử dụng _setupRole
    }

    modifier onlyBoardMember() {
        if (!roleManagementExternal.hasRole(roleManagementExternal.BOARD_ROLE(), msg.sender)) revert IM_NotBoard();
        _;
    }

    modifier onlySupplier() {
        if (!roleManagementExternal.hasRole(roleManagementExternal.SUPPLIER_ROLE(), msg.sender)) revert IM_NotSuppl();
        SupplierInfo storage sup = suppliers[msg.sender];
        if (!(sup.exists && sup.isApprovedByBoard)) revert IM_SupplNotApprv();
        _;
    }

    modifier onlyStoreDirector() {
        if (!roleManagementExternal.hasRole(roleManagementExternal.STORE_DIRECTOR_ROLE(), msg.sender)) revert IM_NotStoreDir();
        _;
    }

    modifier onlyWarehouseDirector() {
        if (!roleManagementExternal.hasRole(roleManagementExternal.WAREHOUSE_DIRECTOR_ROLE(), msg.sender)) revert IM_NotWhDir();
        _;
    }
    
    modifier onlyStoreManagerOfThisStore(address _storeAddress) {
        PhysicalLocationInfo storage loc = physicalLocations[_storeAddress];
        if (!(loc.exists && keccak256(abi.encodePacked(loc.locationType)) == keccak256(abi.encodePacked("STORE")))) revert IM_StoreNotValid();
        if (loc.manager != msg.sender) revert IM_NotStoreMgr();
        _;
    }

    function _getBoardApproval(address[] memory _approvers) internal view returns (bool) {
        if (_approvers.length == 0) return false;
        uint256 totalApprovalShares = 0;
        address[] memory processedApprovers = new address[](_approvers.length);
        uint processedCount = 0;
        for (uint i = 0; i < _approvers.length; i++) {
            address approver = _approvers[i];
            if (approver == msg.sender) revert IM_SelfApprove();
            if (!roleManagementExternal.hasRole(roleManagementExternal.BOARD_ROLE(), approver)) revert IM_ApproverNotBoard();
            bool alreadyProcessed = false;
            for (uint j = 0; j < processedCount; j++) {
                if (processedApprovers[j] == approver) {
                    alreadyProcessed = true;
                    break;
                }
            }
            if (alreadyProcessed) revert IM_DupApprover();
            totalApprovalShares += roleManagementExternal.getSharesPercentage(approver);
            processedApprovers[processedCount++] = approver;
        }
        return totalApprovalShares > 5000;
    }

    function proposeNewItem(string calldata _itemId, string calldata _name /*, string calldata _description, string calldata _category */) external onlyBoardMember {
        if (items[_itemId].exists) revert IM_ItemExists();
        if (bytes(_itemId).length == 0) revert IM_EmptyItemId();
        items[_itemId] = ItemInfo({
            itemId: _itemId, 
            name: _name, 
            // description: _description, // Bỏ
            // category: _category,       // Bỏ
            exists: true, 
            isApprovedByBoard: false, 
            proposer: msg.sender, 
            referencePriceCeiling: 0
        });
        // if (!_itemExistsInArray(_itemId)) { itemIds.push(_itemId); } // Bỏ nếu bỏ mảng itemIds
        emit ItemProposed(_itemId, _name, msg.sender);
    }

    function approveProposedItem(string calldata _itemId, uint128 _referencePriceCeiling, address[] calldata _approvers) external onlyBoardMember {
        ItemInfo storage item = items[_itemId];
        if (!item.exists) revert IM_ItemNotFound();
        if (item.isApprovedByBoard) revert IM_ItemApproved();
        if (_referencePriceCeiling == 0) revert IM_InvalidRefPrice();
        if (!_getBoardApproval(_approvers)) revert IM_BoardReject();
        item.isApprovedByBoard = true;
        item.referencePriceCeiling = _referencePriceCeiling;
        emit ItemApprovedByBoard(_itemId, _referencePriceCeiling, msg.sender);
    }
    
    function proposeNewPhysicalLocation(address _locationId, string calldata _name, string calldata _locationType) external onlyBoardMember {
        if (physicalLocations[_locationId].exists) revert IM_LocExists();
        if (_locationId == address(0)) revert IM_InvalidLocAddr();
        bytes32 typeHash = keccak256(abi.encodePacked(_locationType));
        if (!(typeHash == keccak256(abi.encodePacked("STORE")) || typeHash == keccak256(abi.encodePacked("WAREHOUSE")))) revert IM_InvalidLocType();
        physicalLocations[_locationId] = PhysicalLocationInfo({ locationId: _locationId, name: _name, locationType: _locationType, manager: address(0), exists: true, isApprovedByBoard: false, designatedSourceWarehouseAddress: address(0) });
        // if (!_locationExistsInArray(_locationId)) { locationAddresses.push(_locationId); } // Bỏ nếu bỏ mảng
        emit PhysicalLocationProposed(_locationId, _name, _locationType, msg.sender);
    }

    function approveProposedPhysicalLocation(address _locationId, address[] calldata _approvers) external onlyBoardMember {
        PhysicalLocationInfo storage loc = physicalLocations[_locationId];
        if (!loc.exists) revert IM_LocNotFound();
        if (loc.isApprovedByBoard) revert IM_LocApproved();
        if (!_getBoardApproval(_approvers)) revert IM_BoardReject();
        loc.isApprovedByBoard = true;
        emit PhysicalLocationApprovedByBoard(_locationId, msg.sender);
    }

    function assignManagerToLocation(address _locationId, address _managerId) external {
        PhysicalLocationInfo storage loc = physicalLocations[_locationId];
        if (!(loc.exists && loc.isApprovedByBoard)) revert IM_LocNotValidApprv();
        if (loc.manager != address(0)) revert IM_MgrExists();
        bytes32 locationTypeHash = keccak256(abi.encodePacked(loc.locationType));
        bytes32 expectedManagerRole;
        bytes32 requiredCallerRole;
        if (locationTypeHash == keccak256(abi.encodePacked("STORE"))) {
            expectedManagerRole = roleManagementExternal.STORE_MANAGER_ROLE();
            requiredCallerRole = roleManagementExternal.STORE_DIRECTOR_ROLE();
        } else if (locationTypeHash == keccak256(abi.encodePacked("WAREHOUSE"))) {
            expectedManagerRole = roleManagementExternal.WAREHOUSE_MANAGER_ROLE();
            requiredCallerRole = roleManagementExternal.WAREHOUSE_DIRECTOR_ROLE();
        } else {
            revert IM_UnknownLocType();
        }
        if (!roleManagementExternal.hasRole(requiredCallerRole, msg.sender)) revert IM_CallerNotAuth();
        if (!roleManagementExternal.hasRole(expectedManagerRole, _managerId)) revert IM_MgrInvalidRole();
        loc.manager = _managerId;
        emit PhysicalLocationManagerAssigned(_locationId, _managerId, msg.sender);
    }

    function setDesignatedSourceWarehouseForStore(address _storeAddress, address _warehouseAddress) external onlyStoreDirector {
        PhysicalLocationInfo storage storeInfo = physicalLocations[_storeAddress];
        if (!(storeInfo.exists && storeInfo.isApprovedByBoard && keccak256(abi.encodePacked(storeInfo.locationType)) == keccak256(abi.encodePacked("STORE")))) revert IM_StoreNotValidApprv();
        if (_warehouseAddress != address(0)) {
            PhysicalLocationInfo memory warehouseInfo = physicalLocations[_warehouseAddress];
            if (!(warehouseInfo.exists && warehouseInfo.isApprovedByBoard && keccak256(abi.encodePacked(warehouseInfo.locationType)) == keccak256(abi.encodePacked("WAREHOUSE")))) revert IM_WhNotValidApprv();
        }
        storeInfo.designatedSourceWarehouseAddress = _warehouseAddress;
        emit StoreDesignatedSourceWarehouseSet(_storeAddress, _warehouseAddress, msg.sender);
    }

    function proposeNewSupplier(address _supplierId, string calldata _name) external onlyBoardMember {
        if (suppliers[_supplierId].exists) revert IM_SupplExists();
        if (_supplierId == address(0)) revert IM_InvalidSupplAddr();
        suppliers[_supplierId] = SupplierInfo({ supplierId: _supplierId, name: _name, isApprovedByBoard: false, exists: true });
        // if(!_supplierExistsInArray(_supplierId)){ supplierAddresses.push(_supplierId); } // Bỏ nếu bỏ mảng
        emit SupplierProposed(_supplierId, _name, msg.sender);
    }
    
    function approveProposedSupplier(address _supplierId, address[] calldata _approvers) external onlyBoardMember {
        SupplierInfo storage sup = suppliers[_supplierId];
        if (!sup.exists) revert IM_SupplNotFound();
        if (sup.isApprovedByBoard) revert IM_SupplApproved();
        if (!_getBoardApproval(_approvers)) revert IM_BoardReject();
        sup.isApprovedByBoard = true;
        emit SupplierApprovedByBoard(_supplierId, msg.sender);
    }

    function _getSupplierItemListingKey(address _supplierAddress, string calldata _itemId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_supplierAddress, _itemId));
    }

    function listSupplierItem(string calldata _itemId, uint128 _price) external onlySupplier {
        ItemInfo memory itemInfo = items[_itemId];
        if (!(itemInfo.exists && itemInfo.isApprovedByBoard)) revert IM_ItemNotGlobApproved();
        bytes32 listingKey = _getSupplierItemListingKey(msg.sender, _itemId);
        if (supplierItemListings[listingKey].exists) revert IM_SupplItemListed();
        if (_price == 0) revert IM_InvalidPrice();
        bool autoApproved = (_price <= itemInfo.referencePriceCeiling && itemInfo.referencePriceCeiling > 0);
        supplierItemListings[listingKey] = SupplierItemListing({ 
            itemId: _itemId, 
            // supplierAddress: msg.sender, // Bỏ nếu key đã bao gồm
            price: _price, 
            isApprovedByBoard: autoApproved, 
            exists: true 
        });
        emit SupplierItemListed(msg.sender, _itemId, _price, autoApproved);
    }

    function approveSupplierItemManuallyByBoard(address _supplierAddress, string calldata _itemId, address[] calldata _approvers) external onlyBoardMember {
        if (!(suppliers[_supplierAddress].exists && suppliers[_supplierAddress].isApprovedByBoard)) revert IM_SupplNotApprv();
        bytes32 listingKey = _getSupplierItemListingKey(_supplierAddress, _itemId);
        SupplierItemListing storage listing = supplierItemListings[listingKey];
        if (!listing.exists) revert IM_SupplItemNotListed();
        if (listing.isApprovedByBoard) revert IM_SupplItemApproved();
        if (!_getBoardApproval(_approvers)) revert IM_BoardReject();
        listing.isApprovedByBoard = true;
        emit SupplierItemManuallyApprovedByBoard(_supplierAddress, _itemId, msg.sender);
    }

    function setStoreItemRetailPrice(address _storeAddress, string calldata _itemId, uint128 _price) external onlyStoreDirector {
        ItemInfo memory itemInfo = items[_itemId];
        if (!(itemInfo.exists && itemInfo.isApprovedByBoard)) revert IM_ItemNotGlobApproved();
        PhysicalLocationInfo storage storeInfo = physicalLocations[_storeAddress];
        if (!(storeInfo.exists && storeInfo.isApprovedByBoard && keccak256(abi.encodePacked(storeInfo.locationType)) == keccak256(abi.encodePacked("STORE")))) revert IM_StoreNotValidApprv();
        if (_price == 0) revert IM_InvalidRetailPrice();
        storeItemRetailPrices[_storeAddress][_itemId] = _price;
        emit RetailPriceSet(_storeAddress, _itemId, _price, msg.sender);
    }

    // BỎ CÁC HÀM _existsInArray NẾU BỎ CÁC MẢNG THEO DÕI
    /*
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
    */

    // --- View Functions ---
    function getItemInfo(string calldata _itemId) external view returns (ItemInfo memory) { return items[_itemId]; }
    function getPhysicalLocationInfo(address _locationId) external view returns (PhysicalLocationInfo memory) { return physicalLocations[_locationId]; }
    function getStoreInfo(address _storeAddress) external view returns (PhysicalLocationInfo memory) {
        PhysicalLocationInfo memory loc = physicalLocations[_storeAddress];
        if (!(loc.exists && keccak256(abi.encodePacked(loc.locationType)) == keccak256(abi.encodePacked("STORE")))) revert IM_StoreNotValid();
        return loc;
    }
    function getWarehouseInfo(address _warehouseAddress) external view returns (PhysicalLocationInfo memory) {
        PhysicalLocationInfo memory loc = physicalLocations[_warehouseAddress];
        if (!(loc.exists && keccak256(abi.encodePacked(loc.locationType)) == keccak256(abi.encodePacked("WAREHOUSE")))) revert IM_StoreNotValid(); // Có thể tạo IM_WarehouseNotValid
        return loc;
    }
    function getSupplierInfo(address _supplierId) external view returns (SupplierInfo memory) { return suppliers[_supplierId]; }
    function getSupplierItemListing(address _supplierAddress, string calldata _itemId) external view returns (SupplierItemListing memory) {
        return supplierItemListings[_getSupplierItemListingKey(_supplierAddress, _itemId)];
    }
    function getItemRetailPriceAtStore(string calldata _itemId, address _storeAddress) external view returns (uint128 price, bool priceExists) { // Trả về uint128
        price = storeItemRetailPrices[_storeAddress][_itemId];
        return (price, price > 0);
    }
    
    // BỎ CÁC HÀM GETALL NẾU BỎ CÁC MẢNG THEO DÕI
    /*
    function getAllItemIds() external view returns (string[] memory) { return itemIds; }
    function getAllLocationAddresses() external view returns (address[] memory) { return locationAddresses; }
    function getAllSupplierAddresses() external view returns (address[] memory) { return supplierAddresses; }
    */
}