// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./Interfaces.sol"; // Import file Interfaces.sol tập trung

contract ItemsPricingAndListing is AccessControl, IItemsPricingAndListingInterface {
    IRoleManagement public roleManagementExternal;
    IItemsManagementCoreInterface public itemsManagementCore; // Để tham chiếu đến ItemsManagementCore

    // --- STRUCT DEFINITIONS ---
    // SupplierItemListing được định nghĩa trong Interfaces.sol

    // --- MAPPINGS ---
    mapping(address => mapping(string => SupplierItemListing)) public override supplierItemListings;
    mapping(address => mapping(string => uint256)) public override storeItemRetailPrices;

    // --- EVENTS (chỉ những event liên quan đến pricing/listing) ---
    event SupplierItemListed(address indexed supplierAddress, string indexed itemId, uint256 price, bool autoApproved);
    event SupplierItemManuallyApprovedByBoard(address indexed supplierAddress, string indexed itemId, address indexed approver);
    event RetailPriceSet(address indexed storeAddress, string indexed itemId, uint256 price, address indexed byStoreDirector);

    constructor(address _roleManagementExternalAddress, address _itemsManagementCoreAddress) {
        require(_roleManagementExternalAddress != address(0), "ItemsPL: Dia chi RM Ngoai khong hop le");
        roleManagementExternal = IRoleManagement(_roleManagementExternalAddress);
        require(_itemsManagementCoreAddress != address(0), "ItemsPL: Dia chi ItemsMCore khong hop le");
        itemsManagementCore = IItemsManagementCoreInterface(_itemsManagementCoreAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyBoardMember() {
        require(roleManagementExternal.hasRole(roleManagementExternal.BOARD_ROLE(), msg.sender), "ItemsPL: Nguoi goi khong phai Thanh vien BDH");
        _;
    }

    modifier onlySupplier() {
        require(roleManagementExternal.hasRole(roleManagementExternal.SUPPLIER_ROLE(), msg.sender), "ItemsPL: Nguoi goi khong phai NCC (RM Ngoai)");
        // Kiểm tra NCC tồn tại và được duyệt trong ItemsManagementCore
        SupplierInfo memory supInfo = itemsManagementCore.getSupplierInfo(msg.sender);
        require(supInfo.exists && supInfo.isApprovedByBoard, "ItemsPL: NCC chua duoc dang ky hoac phe duyet");
        _;
    }

    modifier onlyStoreDirector() {
        bytes32 sdRole = roleManagementExternal.STORE_DIRECTOR_ROLE();
        require(roleManagementExternal.hasRole(sdRole, msg.sender), "ItemsPL: Nguoi goi thieu vai tro GIAM_DOC_CH (RM Ngoai)");
        _;
    }
    
    // _getBoardApproval có thể được giữ lại ở đây hoặc ItemsManagementCore có thể cung cấp 1 hàm public nếu cần
    function _getBoardApproval(address[] memory _approvers) internal view returns (bool) {
        if (_approvers.length == 0) return false;
        uint256 totalApprovalShares = 0;
        address[] memory processedApprovers = new address[](_approvers.length);
        uint processedCount = 0;

        for (uint i = 0; i < _approvers.length; i++) {
            address approver = _approvers[i];
            require(approver != msg.sender, "ItemsPL: Nguoi de xuat khong the tu phe duyet");
            require(roleManagementExternal.hasRole(roleManagementExternal.BOARD_ROLE(), approver), "ItemsPL: Nguoi phe duyet khong phai thanh vien BDH");

            bool alreadyProcessed = false;
            for (uint j = 0; j < processedCount; j++) {
                if (processedApprovers[j] == approver) {
                    alreadyProcessed = true;
                    break;
                }
            }
            require(!alreadyProcessed, "ItemsPL: Nguoi phe duyet bi trung lap");
            totalApprovalShares += roleManagementExternal.getSharesPercentage(approver);
            processedApprovers[processedCount] = approver;
            processedCount++;
        }
        return totalApprovalShares > 5000; // 5000 means > 50.00%
    }


    // --- NIÊM YẾT VÀ PHÊ DUYỆT MẶT HÀNG CỦA NHÀ CUNG CẤP ---
    function listSupplierItem(string calldata _itemId, uint256 _price) external override onlySupplier {
        ItemInfo memory itemInfo = itemsManagementCore.getItemInfo(_itemId); // Gọi đến ItemsManagementCore
        require(itemInfo.exists && itemInfo.isApprovedByBoard, "ItemsPL: Mat hang khong ton tai hoac chua duoc BDH phe duyet chung");
        require(!supplierItemListings[msg.sender][_itemId].exists, "ItemsPL: Mat hang cua NCC da duoc niem yet");
        require(_price > 0, "ItemsPL: Gia phai la so duong");

        bool autoApproved = (itemInfo.referencePriceCeiling > 0 && _price <= itemInfo.referencePriceCeiling);

        supplierItemListings[msg.sender][_itemId] = SupplierItemListing({
            itemId: _itemId,
            supplierAddress: msg.sender,
            price: _price,
            isApprovedByBoard: autoApproved,
            exists: true
        });
        emit SupplierItemListed(msg.sender, _itemId, _price, autoApproved);
    }

    function approveSupplierItemManuallyByBoard(address _supplierAddress, string calldata _itemId, address[] calldata _approvers) external override onlyBoardMember {
        SupplierInfo memory supInfo = itemsManagementCore.getSupplierInfo(_supplierAddress); // Gọi đến ItemsManagementCore
        require(supInfo.exists && supInfo.isApprovedByBoard, "ItemsPL: NCC khong ton tai hoac chua duoc BDH phe duyet");
        
        SupplierItemListing storage listing = supplierItemListings[_supplierAddress][_itemId];
        require(listing.exists, "ItemsPL: Mat hang cua NCC chua duoc niem yet");
        require(!listing.isApprovedByBoard, "ItemsPL: Mat hang nay cua NCC da duoc phe duyet roi");
        require(_getBoardApproval(_approvers), "ItemsPL: Khong du ty le co phan BDH phe duyet cho mat hang NCC nay");

        listing.isApprovedByBoard = true;
        emit SupplierItemManuallyApprovedByBoard(_supplierAddress, _itemId, msg.sender);
    }

    // --- THIẾT LẬP GIÁ BÁN LẺ TẠI CỬA HÀNG ---
    function setStoreItemRetailPrice(address _storeAddress, string calldata _itemId, uint256 _price) external override onlyStoreDirector {
        ItemInfo memory itemInfo = itemsManagementCore.getItemInfo(_itemId); // Gọi đến ItemsManagementCore
        require(itemInfo.exists && itemInfo.isApprovedByBoard, "ItemsPL: Mat hang khong ton tai hoac chua duoc BDH phe duyet");
        
        PhysicalLocationInfo memory storeInfo = itemsManagementCore.getStoreInfo(_storeAddress); // Gọi đến ItemsManagementCore
        require(storeInfo.exists && storeInfo.isApprovedByBoard && keccak256(abi.encodePacked(storeInfo.locationType)) == keccak256(abi.encodePacked("STORE")), "ItemsPL: Cua hang khong ton tai, chua duoc BDH phe duyet, hoac khong phai la cua hang");
        require(_price > 0, "ItemsPL: Gia le phai la so duong");

        storeItemRetailPrices[_storeAddress][_itemId] = _price;
        emit RetailPriceSet(_storeAddress, _itemId, _price, msg.sender);
    }

    // --- VIEW FUNCTIONS (implementing IItemsPricingAndListingInterface) ---
    function getSupplierItemDetails(address _supplierAddress, string calldata _itemId) external view override returns (SupplierItemListing memory) {
        return supplierItemListings[_supplierAddress][_itemId];
    }

    function getItemRetailPriceAtStore(string calldata _itemId, address _storeAddress) external view override returns (uint256 price, bool priceExists) {
        price = storeItemRetailPrices[_storeAddress][_itemId];
        return (price, price > 0);
    }
}
