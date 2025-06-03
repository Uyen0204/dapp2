// migrations/5_deploy_company_treasury.js
const RoleManagement = artifacts.require("RoleManagement");
const ItemsManagementCore = artifacts.require("ItemsManagementCore");
// ItemsPricingAndListing không cần thiết cho constructor của CompanyTreasuryManager
const CompanyTreasuryManager = artifacts.require("CompanyTreasuryManager");

module.exports = async function (deployer, network, accounts) {
  const roleManagementInstance = await RoleManagement.deployed();
  const itemsManagementCoreInstance = await ItemsManagementCore.deployed();

  if (!roleManagementInstance) {
    console.error("LỖI: RoleManagement contract chưa được deploy! Không thể deploy CompanyTreasuryManager.");
    return;
  }
  if (!itemsManagementCoreInstance) {
    console.error("LỖI: ItemsManagementCore contract chưa được deploy! Không thể deploy CompanyTreasuryManager.");
    return;
  }

  const totalCapitalFromRM = await roleManagementInstance.totalCapital();
  console.log(`Tổng vốn từ RoleManagement cần cho CTM: ${web3.utils.fromWei(totalCapitalFromRM, 'ether')} ETH`);

  const deployerAccount = accounts[0];
  const deployerBalance = await web3.eth.getBalance(deployerAccount);
  console.log(`Số dư của người deploy (${deployerAccount}): ${web3.utils.fromWei(deployerBalance, 'ether')} ETH`);

  if (web3.utils.toBN(deployerBalance).lt(web3.utils.toBN(totalCapitalFromRM))) {
    console.warn(`CẢNH BÁO: Số dư của người deploy (${web3.utils.fromWei(deployerBalance, 'ether')} ETH) có thể không đủ để gửi ${web3.utils.fromWei(totalCapitalFromRM, 'ether')} ETH cho CompanyTreasuryManager.`);
  }

  console.log(`Deploying CompanyTreasuryManager với:`);
  console.log(`  - RoleManagement tại: ${roleManagementInstance.address}`);
  console.log(`  - ItemsManagementCore tại: ${itemsManagementCoreInstance.address}`);
  console.log(`  - Vốn ban đầu dự kiến: ${web3.utils.fromWei(totalCapitalFromRM, 'ether')} ETH`);
  console.log(`  - Gửi kèm msg.value: ${web3.utils.fromWei(totalCapitalFromRM, 'ether')} ETH từ ${deployerAccount}`);

  await deployer.deploy(
    CompanyTreasuryManager,
    roleManagementInstance.address,
    itemsManagementCoreInstance.address, // Constructor của CTM chỉ cần ItemsManagementCore
    totalCapitalFromRM,
    {
      from: deployerAccount,
      value: totalCapitalFromRM
    }
  );

  const ctmInstance = await CompanyTreasuryManager.deployed();
  console.log("CompanyTreasuryManager đã được deploy tại:", ctmInstance.address);

  const ctmBalance = await web3.eth.getBalance(ctmInstance.address);
  console.log(`Số dư của CompanyTreasuryManager sau khi deploy: ${web3.utils.fromWei(ctmBalance, 'ether')} ETH`);
};