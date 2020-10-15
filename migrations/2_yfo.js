const erc20_0 = artifacts.require("MockERC20.sol");
const erc20_1 = artifacts.require("MockERC20.sol");
const erc20_2 = artifacts.require("MockERC20.sol");
const YFO = artifacts.require("YFOToken.sol");
const YFODistribution = artifacts.require("YFODistribution.sol");

module.exports = async function(deployer, network, accounts) {
  console.log('accounts[0] = ', accounts[0])

  await deployer.deploy(erc20_0, "LP0", "LP0", '1000', {from: accounts[0]});
  await deployer.deploy(erc20_1, "LP1", "LP1", '1000', {from: accounts[0]});
  await deployer.deploy(erc20_2, "LP2", "LP2", '1000', {from: accounts[0]});

  const lp0 = await erc20_0.deployed();
  const lp1 = await erc20_1.deployed();
  const lp2 = await erc20_2.deployed();

  await deployer.deploy(YFO, {from: accounts[0]})
  const yfo = await YFO.deployed();
  await deployer.deploy(YFODistribution, yfo.address, '4359654017857142', '8881500', [lp0.address, lp1.address, lp2.address], [4, 3, 2], {from: accounts[0]})
  const yfoDist = await YFODistribution.deployed();
  await yfo.transferOwnership(yfoDist.address, {from: accounts[0]});

  console.log("lp0.address     = ", lp0.address);
  console.log("lp1.address     = ", lp0.address);
  console.log("lp2.address     = ", lp0.address);
  
  console.log("yfo.address     = ", yfo.address)
  console.log("yfodist.address = ", yfoDist.address)

  const saver = require("../save_address.js");
  saver("YFO_Migrate", {
        LP0_Addr: lp0.address,
        LP1_Addr: lp1.address,
        LP2_Addr: lp2.address,
        YFO_Addr: yfo.address,
        YFODistribution_Addr: yfoDist.address,
    });
};
