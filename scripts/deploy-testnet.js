const { ethers, network } = require('hardhat');
require('@nomiclabs/hardhat-ethers');

async function main() {
  if (network.name !== 'ropsten' && network.name != 'rinkeby') {
    throw new Error('Invalid network');
  }
  let [deployer] = await ethers.getSigners();

  let amount = '8000000000000000000000000'; // 8m moma
  let farmFactory, farmGenerator, farm;

  let rewardPerBlock = '3000000000000000000';

  let startBlock = (await ethers.provider.getBlockNumber()) + 200;
  console.log('Startblock: ', startBlock);
  let firstCycleRate = 2;
  let initRate = 1;
  let reducingRate = 95;
  let reducingCycle = 195000; // 1 month

  let percentForVesting = 100;
  let vestingDuration = 1170000; // 6 months

  let momaToken, weth, lpToken, uniswapV2Factory, uniswapV2Router;
  let uniswapV2RouterAddress = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D';

  console.log('Deploy contract with the account: ', deployer.address);

  console.log('\nDeploy Test MOMA');
  let TestERC20 = await ethers.getContractFactory('TestERC20');
  momaToken = await TestERC20.connect(deployer).deploy('MOchi MArket Token', 'MOMA');
  await momaToken.deployed();
  await momaToken.connect(deployer).mint(deployer.address, amount);

  uniswapV2Router = await ethers.getContractAt('IUniswapV2Router', uniswapV2RouterAddress);

  weth = await ethers.getContractAt('WETH9', await uniswapV2Router.WETH());

  uniswapV2Factory = await ethers.getContractAt(
    'IUniswapV2Factory',
    await uniswapV2Router.factory()
  );

  let tx = await uniswapV2Factory.connect(deployer).createPair(momaToken.address, weth.address);
  await tx.wait();

  lpToken = await uniswapV2Factory.getPair(momaToken.address, weth.address);

  console.log('\nDeploy Farm Factory...');
  let FarmFactory = await ethers.getContractFactory('FarmFactory');
  farmFactory = await FarmFactory.connect(deployer).deploy();
  await farmFactory.deployed();

  console.log('\nDeploy Farm Generator...');
  let FarmGenerator = await ethers.getContractFactory('FarmGenerator');
  farmGenerator = await FarmGenerator.connect(deployer).deploy(
    farmFactory.address,
    uniswapV2Factory.address
  );
  await farmGenerator.deployed();

  await farmFactory.connect(deployer).adminAllowFarmGenerator(farmGenerator.address, true);

  console.log('\nCreate Farm...');

  console.log(farmGenerator.address);
  tx = await momaToken.connect(deployer).approve(farmGenerator.address, amount);
  await tx.wait();
  tx = await farmGenerator
    .connect(deployer)
    .createFarm(
      momaToken.address,
      amount,
      lpToken,
      rewardPerBlock,
      startBlock,
      [firstCycleRate, initRate, reducingRate, reducingCycle],
      [percentForVesting, vestingDuration]
    );

  await tx.wait();

  farm = await ethers.getContractAt('Farm', await farmFactory.farmAtIndex(0));
  console.log('\n\nAll setup successfully...');
  console.log('LP Token: ', lpToken);
  console.log('MOMA: ', momaToken.address);
  console.log('WETH: ', weth.address);
  console.log('Farm Factory: ', farmFactory.address);
  console.log('Farm Generator: ', farmGenerator.address);
  console.log('Farm: ', farm.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });