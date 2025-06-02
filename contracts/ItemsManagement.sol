// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4; // Đảm bảo phiên bản >= 0.8.4

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./Interfaces.sol"; // Import file Interfaces.sol tập trung

// --- CUSTOM ERROR DEFINITIONS ---
// Lỗi chung
error InvalidAddress(address addr);
error CallerNotAuthorized(address caller, bytes32 requiredRole);
error AlreadyExists(string entityType, string entityId);
error AlreadyExistsAddress(string entityType, address entityAddr);
error NotFound(string entityType, string entityId);
error NotFoundAddress(string entityType, address entityAddr);
error NotApproved(string entityType, string entityId);
error NotApprovedAddress(string entityType, address entityAddr);
error StringTooShort(string fieldName);
error ValueMustBePositive(string fieldName);
error ApprovalFailed(string reason);
error InvalidStateForAction(string action);
error CannotSelfApprove(address proposer);
error DuplicateApprover(address approver);

// Lỗi cụ thể cho ItemsManagement
error InvalidLocationType(string providedType);
error ManagerAlreadyAssigned(address locationId, address currentManager);
error ManagerRoleMissing(address candidateManager, bytes32 expectedRole);
error NoDesignatedSourceWarehouse(address storeAddress);
error InvalidSourceWarehouse(address warehouseAddress);
error SupplierMissingRole(address supplierAddress);
// error PriceTooHigh(uint256 price, uint256 ceiling); // Có thể không cần nếu chỉ auto-approve

contract ItemsManagement is AccessControl {
    IRoleManagement public roleManagementExternal;

    struct ItemInfo {
        string itemId;
        string name;
        string description;
        string category;
        bool exists;
        bool isApprovedByBoard;
        address proposer;
        uint256 referencePriceCeiling;
    }

    // --- MAPPINGS ---
    mapping(string => ItemInfo) public items;
    mapping(address => PhysicalLocationInfo) public physicalLocations;
    mapping(address => SupplierInfo) public suppliers;
    mapping(address => mapping(string => SupplierItemListing)) public supplierItemListings;
    mapping(address => mapping(string => uint256)) public storeItemRetailPrices;

    // --- ARRAYS FOR ITERATION ---
    string[] public itemIds;
    address[] public locationAddresses;
    address[] public supplierAddresses;

    // --- EVENTS ---
    event ItemProposed(string indexed itemId, string name, address indexed proposer);
    event ItemApprovedByBoard(string indexed itemId, uint256 referencePriceCeiling, address indexed finalApprover);
    event PhysicalLocationProposed(address indexed locationId, string name, string locationType, address indexed proposer);
    event PhysicalLocationApprovedByBoard(address indexed locationId, address indexed finalApprover);
    event SupplierProposed(address indexed supplierId, string name, address indexed proposer);
    event SupplierApprovedByBoard(address indexed supplierId, address indexed finalApprover);
    event PhysicalLocationManagerAssigned(address indexed locationId, address newManager, address indexed byDirector);
    event StoreDesignatedSourceWarehouseSet(address indexed storeAddress, address indexed designatedWarehouse, address indexed byStoreDirector);
    event SupplierItemListed(address indexed supplierAddress, string indexed itemId, uint256 price, bool autoApproved);
    event SupplierItemManuallyApprovedByBoard(address indexed supplierAddress, string indexed itemId, address indexed approver);
    event RetailPriceSet(address indexed storeAddress, string indexed itemId, uint256 price, address indexed byStoreDirector);

    // --- CONSTRUCTOR ---
    constructor(address _roleManagementExternalAddress) {
        if (_roleManagementExternalAddress == address(0)) {
            revert InvalidAddress(_roleManagementExternalAddress);
        }
        roleManagementExternal = IRoleManagement(_roleManagementExternalAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // --- MODIFIERS ---
    modifier onlyBoardMember() {
        if (!roleManagementExternal.hasRole(roleManagementExternal.BOARD_ROLE(), msg.sender)) {
            revert CallerNotAuthorized(msg.sender, roleManagementExternal.BOARD_ROLE());
        }
        _;
    }

    modifier onlySupplier() {
        if (!roleManagementExternal.hasRole(roleManagementExternal.SUPPLIER_ROLE(), msg.sender)) {
            revert CallerNotAuthorized(msg.sender, roleManagementExternal.SUPPLIER_ROLE());
        }
        SupplierInfo storage sup = suppliers[msg.sender];
        if (!sup.exists || !sup.isApprovedByBoard) {
            revert NotApprovedAddress("Supplier", msg.sender);
        }
        _;
    }

    modifier onlyStoreDirector() {
        bytes32 sdRole = roleManagementExternal.STORE_DIRECTOR_ROLE();
        if (!roleManagementExternal.hasRole(sdRole, msg.sender)) {
            revert CallerNotAuthorized(msg.sender, sdRole);
        }
        _;
    }

    modifier onlyWarehouseDirector() {
        bytes32 wdRole = roleManagementExternal.WAREHOUSE_DIRECTOR_ROLE();
        if (!roleManagementExternal.hasRole(wdRole, msg.sender)) {
            revert CallerNotAuthorized(msg.sender, wdRole);
        }
        _;
    }

    // Modifier này không còn cần thiết nếu logic kiểm tra được đưa vào hàm
    // modifier onlyStoreManagerOfThisStore(address _storeAddress) { ... }


    // --- INTERNAL FUNCTIONS ---
    function _getBoardApproval(address[] memory _approvers) internal view returns (bool) {
        if (_approvers.length == 0) return false;
        uint256 totalApprovalShares = 0;
        uint processedCount = 0;
        // Kích thước mảng processedApprovers phải bằng _approvers.length
        // để tránh out-of-bounds access nếu tất cả approvers đều hợp lệ.
        address[] memory processedApprovers = new address[](_approvers.length);


        for (uint i = 0; i < _approvers.length; i++) {
            address approver = _approvers[i];

            if (approver == msg.sender) {
                revert CannotSelfApprove(msg.sender);
            }
            if (!roleManagementExternal.hasRole(roleManagementExternal.BOARD_ROLE(), approver)) {
                revert CallerNotAuthorized(approver, roleManagementExternal.BOARD_ROLE());
            }

            for (uint j = 0; j < processedCount; j++) {
                if (processedApprovers[j] == approver) {
                    revert DuplicateApprover(approver);
                }
            }
            
            totalApprovalShares += roleManagementExternal.getSharesPercentage(approver);
            processedApprovers[processedCount] = approver;
            processedCount++;
        }
        if (totalApprovalShares <= 5000) { // 5000 means <= 50.00%
            return false;
        }
        return true;
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

    // --- ITEM MANAGEMENT BY BOARD ---
    function proposeNewItem(string calldata _itemId, string calldata _name, string calldata _description, string calldata _category) external onlyBoardMember {
        if (items[_itemId].exists) {
            revert AlreadyExists("Item", _itemId);
        }
        if (bytes(_itemId).length == 0) {
            revert StringTooShort("itemId");
        }

        items[_itemId] = ItemInfo({
            itemId: _itemId, name: _name, description: _description, category: _category,
            exists: true, isApprovedByBoard: false, proposer: msg.sender, referencePriceCeiling: 0
        });
        if (!_itemExistsInArray(_itemId)) { itemIds.push(_itemId); }
        emit ItemProposed(_itemId, _name, msg.sender);
    }

    function approveProposedItem(string calldata _itemId, uint256 _referencePriceCeiling, address[] calldata _approvers) external onlyBoardMember {
        ItemInfo storage item = items[_itemId];
        if (!item.exists) { revert NotFound("Item", _itemId); }
        if (item.isApprovedByBoard) { revert InvalidStateForAction("Item already approved"); }
        if (_referencePriceCeiling == 0) { revert ValueMustBePositive("referencePriceCeiling"); }
        if (!_getBoardApproval(_approvers)) { revert ApprovalFailed("Board approval failed for item"); }

        item.isApprovedByBoard = true;
        item.referencePriceCeiling = _referencePriceCeiling;
        emit ItemApprovedByBoard(_itemId, _referencePriceCeiling, msg.sender);
    }

    // --- PHYSICAL LOCATION MANAGEMENT BY BOARD ---
    function proposeNewPhysicalLocation(address _locationId, string calldata _name, string calldata _locationType) external onlyBoardMember {
        if (physicalLocations[_locationId].exists) { revert AlreadyExistsAddress("PhysicalLocation", _locationId); }
        if (_locationId == address(0)) { revert InvalidAddress(_locationId); }
        bytes32 typeHash = keccak256(abi.encodePacked(_locationType));
        if (typeHash != keccak256(abi.encodePacked("STORE")) && typeHash != keccak256(abi.encodePacked("WAREHOUSE"))) {
            revert InvalidLocationType(_locationType);
        }

        physicalLocations[_locationId] = PhysicalLocationInfo({
            locationId: _locationId, name: _name, locationType: _locationType, manager: address(0),
            exists: true, isApprovedByBoard: false, designatedSourceWarehouseAddress: address(0)
        });
        if (!_locationExistsInArray(_locationId)) { locationAddresses.push(_locationId); }
        emit PhysicalLocationProposed(_locationId, _name, _locationType, msg.sender);
    }

    function approveProposedPhysicalLocation(address _locationId, address[] calldata _approvers) external onlyBoardMember {
        PhysicalLocationInfo storage loc = physicalLocations[_locationId];
        if (!loc.exists) { revert NotFoundAddress("PhysicalLocation", _locationId); }
        if (loc.isApprovedByBoard) { revert InvalidStateForAction("Location already approved"); }
        if (!_getBoardApproval(_approvers)) { revert ApprovalFailed("Board approval failed for location"); }

        loc.isApprovedByBoard = true;
        emit PhysicalLocationApprovedByBoard(_locationId, msg.sender);
    }

    function assignManagerToLocation(address _locationId, address _managerId) external { // Logic for director role inside
        PhysicalLocationInfo storage loc = physicalLocations[_locationId];
        if (!loc.exists) { revert NotFoundAddress("Location", _locationId); }
        if (!loc.isApprovedByBoard) { revert NotApprovedAddress("Location", _locationId); }
        if (loc.manager != address(0)) { revert ManagerAlreadyAssigned(_locationId, loc.manager); }
        if (_managerId == address(0)) { revert InvalidAddress(_managerId); }

        bytes32 expectedManagerRole;
        bytes32 requiredDirectorRole;
        bool isStore = (keccak256(abi.encodePacked(loc.locationType)) == keccak256(abi.encodePacked("STORE")));

        if (isStore) {
            expectedManagerRole = roleManagementExternal.STORE_MANAGER_ROLE();
            requiredDirectorRole = roleManagementExternal.STORE_DIRECTOR_ROLE();
        } else { // Must be WAREHOUSE
            expectedManagerRole = roleManagementExternal.WAREHOUSE_MANAGER_ROLE();
            requiredDirectorRole = roleManagementExternal.WAREHOUSE_DIRECTOR_ROLE();
        }

        if (!roleManagementExternal.hasRole(requiredDirectorRole, msg.sender)) {
            revert CallerNotAuthorized(msg.sender, requiredDirectorRole);
        }
        if (!roleManagementExternal.hasRole(expectedManagerRole, _managerId)) {
            revert ManagerRoleMissing(_managerId, expectedManagerRole);
        }

        loc.manager = _managerId;
        emit PhysicalLocationManagerAssigned(_locationId, _managerId, msg.sender);
    }

    function setDesignatedSourceWarehouseForStore(address _storeAddress, address _warehouseAddress) external onlyStoreDirector {
        PhysicalLocationInfo storage storeInfo = physicalLocations[_storeAddress];
        if (!storeInfo.exists || !storeInfo.isApprovedByBoard || keccak256(abi.encodePacked(storeInfo.locationType)) != keccak256(abi.encodePacked("STORE"))) {
            revert NotApprovedAddress("Store for setting source warehouse", _storeAddress);
        }

        if (_warehouseAddress != address(0)) {
            PhysicalLocationInfo memory warehouseInfo = physicalLocations[_warehouseAddress];
            if (!warehouseInfo.exists || !warehouseInfo.isApprovedByBoard || keccak256(abi.encodePacked(warehouseInfo.locationType)) != keccak256(abi.encodePacked("WAREHOUSE"))) {
                revert InvalidSourceWarehouse(_warehouseAddress);
            }
        }
        storeInfo.designatedSourceWarehouseAddress = _warehouseAddress;
        emit StoreDesignatedSourceWarehouseSet(_storeAddress, _warehouseAddress, msg.sender);
    }

    // --- SUPPLIER MANAGEMENT BY BOARD ---
    function proposeNewSupplier(address _supplierId, string calldata _name) external onlyBoardMember {
        if (suppliers[_supplierId].exists) { revert AlreadyExistsAddress("Supplier", _supplierId); }
        if (_supplierId == address(0)) { revert InvalidAddress(_supplierId); }
        if (!roleManagementExternal.hasRole(roleManagementExternal.SUPPLIER_ROLE(), _supplierId)) {
            revert SupplierMissingRole(_supplierId);
        }

        suppliers[_supplierId] = SupplierInfo({
            supplierId: _supplierId, name: _name, isApprovedByBoard: false, exists: true
        });
        if (!_supplierExistsInArray(_supplierId)) { supplierAddresses.push(_supplierId); }
        emit SupplierProposed(_supplierId, _name, msg.sender);
    }

    function approveProposedSupplier(address _supplierId, address[] calldata _approvers) external onlyBoardMember {
        SupplierInfo storage sup = suppliers[_supplierId];
        if (!sup.exists) { revert NotFoundAddress("Supplier", _supplierId); }
        if (sup.isApprovedByBoard) { revert InvalidStateForAction("Supplier already approved"); }
        if (!_getBoardApproval(_approvers)) { revert ApprovalFailed("Board approval failed for supplier"); }

        sup.isApprovedByBoard = true;
        emit SupplierApprovedByBoard(_supplierId, msg.sender);
    }

    // --- SUPPLIER ITEM LISTING AND APPROVAL ---
    function listSupplierItem(string calldata _itemId, uint256 _price) external onlySupplier {
        ItemInfo memory itemInfo = items[_itemId];
        if (!itemInfo.exists || !itemInfo.isApprovedByBoard) { revert NotApproved("Item for listing", _itemId); }
        if (supplierItemListings[msg.sender][_itemId].exists) { revert AlreadyExists("Supplier item listing", _itemId); } // Consider supplier in ID
        if (_price == 0) { revert ValueMustBePositive("price"); }

        bool autoApproved = (itemInfo.referencePriceCeiling > 0 && _price <= itemInfo.referencePriceCeiling);
        supplierItemListings[msg.sender][_itemId] = SupplierItemListing({
            itemId: _itemId, supplierAddress: msg.sender, price: _price,
            isApprovedByBoard: autoApproved, exists: true
        });
        emit SupplierItemListed(msg.sender, _itemId, _price, autoApproved);
    }

    function approveSupplierItemManuallyByBoard(address _supplierAddress, string calldata _itemId, address[] calldata _approvers) external onlyBoardMember {
        if (!suppliers[_supplierAddress].exists || !suppliers[_supplierAddress].isApprovedByBoard) {
            revert NotApprovedAddress("Supplier for item approval", _supplierAddress);
        }
        SupplierItemListing storage listing = supplierItemListings[_supplierAddress][_itemId];
        if (!listing.exists) { revert NotFound("Supplier item listing for approval", _itemId); } // Consider supplier in ID
        if (listing.isApprovedByBoard) { revert InvalidStateForAction("Supplier item already approved"); }
        if (!_getBoardApproval(_approvers)) { revert ApprovalFailed("Board approval failed for supplier item"); }

        listing.isApprovedByBoard = true;
        emit SupplierItemManuallyApprovedByBoard(_supplierAddress, _itemId, msg.sender);
    }

    // --- STORE ITEM RETAIL PRICE ---
    function setStoreItemRetailPrice(address _storeAddress, string calldata _itemId, uint256 _price) external onlyStoreDirector {
        if (!items[_itemId].exists || !items[_itemId].isApprovedByBoard) {
            revert NotApproved("Item for retail price setting", _itemId);
        }
        PhysicalLocationInfo memory storeInfo = physicalLocations[_storeAddress];
        if (!storeInfo.exists || !storeInfo.isApprovedByBoard || keccak256(abi.encodePacked(storeInfo.locationType)) != keccak256(abi.encodePacked("STORE"))) {
            revert NotApprovedAddress("Store for retail price setting", _storeAddress);
        }
        if (_price == 0) { revert ValueMustBePositive("price"); }

        storeItemRetailPrices[_storeAddress][_itemId] = _price;
        emit RetailPriceSet(_storeAddress, _itemId, _price, msg.sender);
    }

    // --- VIEW FUNCTIONS ---
    function getItemInfo(string calldata _itemId) external view returns (ItemInfo memory) {
        return items[_itemId];
    }
    function getPhysicalLocationInfo(address _locationId) external view returns (PhysicalLocationInfo memory) {
        return physicalLocations[_locationId];
    }
    function getStoreInfo(address _storeAddress) external view returns (PhysicalLocationInfo memory) {
        PhysicalLocationInfo memory loc = physicalLocations[_storeAddress];
        if (!loc.exists || keccak256(abi.encodePacked(loc.locationType)) != keccak256(abi.encodePacked("STORE"))) {
            revert NotFoundAddress("Store", _storeAddress); // Or InvalidLocationType
        }
        return loc;
    }
    function getWarehouseInfo(address _warehouseAddress) external view returns (PhysicalLocationInfo memory) {
        PhysicalLocationInfo memory loc = physicalLocations[_warehouseAddress];
        if (!loc.exists || keccak256(abi.encodePacked(loc.locationType)) != keccak256(abi.encodePacked("WAREHOUSE"))) {
             revert NotFoundAddress("Warehouse", _warehouseAddress); // Or InvalidLocationType
        }
        return loc;
    }
    function getSupplierInfo(address _supplierId) external view returns (SupplierInfo memory) {
        return suppliers[_supplierId];
    }
    function getSupplierItemDetails(address _supplierAddress, string calldata _itemId) external view returns (SupplierItemListing memory) {
        return supplierItemListings[_supplierAddress][_itemId];
    }
    function getItemRetailPriceAtStore(string calldata _itemId, address _storeAddress) external view returns (uint256 price, bool priceExists) {
        price = storeItemRetailPrices[_storeAddress][_itemId];
        return (price, price > 0); // Assuming price 0 means not set
    }
    function getAllItemIds() external view returns (string[] memory) { return itemIds; }
    function getAllLocationAddresses() external view returns (address[] memory) { return locationAddresses; }
    function getAllSupplierAddresses() external view returns (address[] memory) { return supplierAddresses; }
}