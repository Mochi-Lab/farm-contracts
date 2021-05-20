const { ethers } = require('hardhat');
const { expect } = require('chai');
const { time, expectRevert } = require('@openzeppelin/test-helpers');

describe('Test Moma Farming', async () => {
  let moma, momaFarm, momaVault, compoundFarm;
  let deployer, alice, bob, jack;
  let startBlock;

  let bobMomaBeforeBalance = '1000000000000000000';
  let jackMomaBeforeBalance = '1000000000000000000';

  let amountToFarm = '2000000000000000000000000';
  let momaPerBlock = '2000000000000000000';

  let firstCycleRate = 6;
  let initRate = 3;
  let reducingRate = 95;
  let reducingCycle = 195000;

  beforeEach(async () => {
    [deployer, alice, bob, jack] = await ethers.getSigners();

    let TestERC20 = await ethers.getContractFactory('TestERC20');
    moma = await TestERC20.connect(deployer).deploy('MOchi MArket Token', 'MOMA');

    let MomaFarm = await ethers.getContractFactory('MomaFarm');
    momaFarm = await MomaFarm.connect(deployer).deploy();

    let MomaVault = await ethers.getContractFactory('MomaVault');
    momaVault = await MomaVault.connect(deployer).deploy(moma.address, momaFarm.address);

    startBlock = parseInt(await time.latestBlock()) + 100;

    await momaFarm
      .connect(deployer)
      .initialize(momaVault.address, momaPerBlock, startBlock, [
        firstCycleRate,
        initRate,
        reducingRate,
        reducingCycle,
      ]);

    await moma.connect(deployer).mint(deployer.address, amountToFarm);
    await moma.connect(deployer).approve(momaVault.address, amountToFarm);
    await momaVault.connect(deployer).depositFunds(amountToFarm);

    let CompoundFarm = await ethers.getContractFactory('CompoundFarm');
    compoundFarm = await CompoundFarm.connect(deployer).deploy(momaFarm.address);
  });

  it('All setup successfully', async () => {
    expect(await momaFarm.moma()).to.be.equal(moma.address);
    expect(await momaFarm.momaVault()).to.be.equal(momaVault.address);
    expect(parseInt(await momaFarm.startBlock())).to.be.equal(startBlock);
    expect(parseInt(await momaFarm.momaPerBlock())).to.be.equal(parseInt(momaPerBlock));
    expect(parseInt(await momaFarm.lastRewardBlock())).to.be.equal(startBlock);
    expect(parseInt(await momaFarm.accMomaPerShare())).to.be.equal(0);
    expect(parseInt(await momaFarm.firstCycleRate())).to.be.equal(firstCycleRate);
    expect(parseInt(await momaFarm.initRate())).to.be.equal(initRate);
    expect(parseInt(await momaFarm.reducingRate())).to.be.equal(reducingRate);
    expect(parseInt(await momaFarm.reducingCycle())).to.be.equal(reducingCycle);

    expect(await compoundFarm.moma()).to.be.equal(moma.address);
  });

  describe('Check multiplier', async () => {
    it('Check multiplier from startBlock to startBlock', async () => {
      expect(parseInt(await momaFarm.getMultiplier(startBlock, startBlock))).to.be.equal(0);
    });

    it('Check multiplier from startBlock to startBlock + 1', async () => {
      expect(parseInt(await momaFarm.getMultiplier(startBlock, startBlock + 1))).to.be.equal(
        firstCycleRate * 1e12 * 1
      );
    });

    it('Check multiplier from startBlock to startBlock + reducingCycle - 1', async () => {
      expect(
        parseInt(await momaFarm.getMultiplier(startBlock, startBlock + reducingCycle - 1))
      ).to.be.equal(firstCycleRate * 1e12 * (reducingCycle - 1));
    });

    it('Check multiplier from startBlock to startBlock + reducingCycle', async () => {
      expect(
        parseInt(await momaFarm.getMultiplier(startBlock, startBlock + reducingCycle))
      ).to.be.equal(firstCycleRate * 1e12 * reducingCycle);
    });

    it('Check multiplier from startBlock to startBlock + reducingCycle + 100', async () => {
      expect(
        parseInt(await momaFarm.getMultiplier(startBlock, startBlock + reducingCycle + 100))
      ).to.be.equal(firstCycleRate * 1e12 * reducingCycle + 100 * initRate * 1e12);
    });

    it('Check multiplier from startBlock to startBlock + reducingCycle * 2', async () => {
      expect(
        parseInt(await momaFarm.getMultiplier(startBlock, startBlock + reducingCycle * 2))
      ).to.be.equal(firstCycleRate * 1e12 * reducingCycle + initRate * 1e12 * reducingCycle);
    });

    it('Check multiplier from startBlock to startBlock + reducingCycle * 2 + 1000', async () => {
      expect(
        parseInt(await momaFarm.getMultiplier(startBlock, startBlock + reducingCycle * 2 + 1000))
      ).to.be.equal(
        firstCycleRate * 1e12 * reducingCycle +
          initRate * 1e12 * reducingCycle +
          ((1e12 * initRate * reducingRate) / 100) * 1000
      );
    });

    it('Check multiplier from startBlock + reducingCycle + 1 to startBlock + reducingCycle * 2 + 1000', async () => {
      expect(
        parseInt(
          await momaFarm.getMultiplier(
            startBlock + reducingCycle + 1,
            startBlock + reducingCycle * 2 + 1000
          )
        )
      ).to.be.equal(
        parseInt(await momaFarm.getMultiplier(startBlock, startBlock + reducingCycle * 2 + 1000)) -
          parseInt(await momaFarm.getMultiplier(startBlock, startBlock + reducingCycle + 1))
      );
    });
  });

  it('Bob deposit successfully first and only bob in pool', async () => {
    await moma.connect(deployer).mint(bob.address, bobMomaBeforeBalance);
    await moma.connect(bob).approve(compoundFarm.address, bobMomaBeforeBalance);
    await compoundFarm.connect(bob).deposit(bobMomaBeforeBalance);
    await time.advanceBlockTo(startBlock + 10);

    expect(parseInt(await momaFarm.pendingMoma(compoundFarm.address))).to.be.equal(
      10 * firstCycleRate * parseInt(momaPerBlock)
    );

    expect(parseInt(await compoundFarm.totalShares())).to.be.equal(parseInt(bobMomaBeforeBalance));

    let userInfo = await compoundFarm.userInfo(bob.address);

    expect(parseInt(userInfo.shares)).to.be.equal(parseInt(bobMomaBeforeBalance));
    expect(parseInt(userInfo.momaAtLastUserAction)).to.be.equal(parseInt(bobMomaBeforeBalance));

    expect(parseInt(await compoundFarm.balanceOf())).to.be.equal(parseInt(bobMomaBeforeBalance));
  });

  it('Bob and Jack deposit successfully before startBlock comes', async () => {
    await moma.connect(deployer).mint(bob.address, bobMomaBeforeBalance);
    await moma.connect(bob).approve(compoundFarm.address, bobMomaBeforeBalance);

    await moma.connect(deployer).mint(jack.address, jackMomaBeforeBalance);
    await moma.connect(jack).approve(compoundFarm.address, jackMomaBeforeBalance);

    await compoundFarm.connect(bob).deposit(bobMomaBeforeBalance);
    await compoundFarm.connect(jack).deposit(jackMomaBeforeBalance);

    await time.advanceBlockTo(startBlock + 10);
    expect(parseInt(await momaFarm.pendingMoma(compoundFarm.address))).to.be.equal(
      10 * firstCycleRate * parseInt(momaPerBlock)
    );

    expect(parseInt(await compoundFarm.totalShares())).to.be.equal(
      parseInt(bobMomaBeforeBalance) + parseInt(jackMomaBeforeBalance)
    );

    let bobInfo = await compoundFarm.userInfo(bob.address);
    expect(parseInt(bobInfo.shares)).to.be.equal(parseInt(bobMomaBeforeBalance));
    expect(parseInt(bobInfo.momaAtLastUserAction)).to.be.equal(parseInt(bobMomaBeforeBalance));

    let jackInfo = await compoundFarm.userInfo(jack.address);
    expect(parseInt(jackInfo.shares)).to.be.equal(parseInt(jackMomaBeforeBalance));
    expect(parseInt(jackInfo.momaAtLastUserAction)).to.be.equal(parseInt(jackMomaBeforeBalance));
  });

  it('Bob deposit successfully before startBlock comes, Jack deposit successfully at startBlock + 10', async () => {
    await moma.connect(deployer).mint(bob.address, bobMomaBeforeBalance);
    await moma.connect(bob).approve(compoundFarm.address, bobMomaBeforeBalance);

    await moma.connect(deployer).mint(jack.address, jackMomaBeforeBalance);
    await moma.connect(jack).approve(compoundFarm.address, jackMomaBeforeBalance);

    await compoundFarm.connect(bob).deposit(bobMomaBeforeBalance);
    await time.advanceBlockTo(startBlock + 10);

    let beforePendingReward = parseInt(await momaFarm.pendingMoma(compoundFarm.address));

    expect(beforePendingReward).to.be.equal(momaPerBlock * firstCycleRate * 10);

    expect(parseInt(await compoundFarm.balanceOf())).to.be.equal(parseInt(bobMomaBeforeBalance));

    await compoundFarm.connect(jack).deposit(jackMomaBeforeBalance);

    expect(parseInt(await compoundFarm.balanceOf())).to.be.equal(
      parseInt(bobMomaBeforeBalance) +
        parseInt(jackMomaBeforeBalance) +
        beforePendingReward +
        parseInt(firstCycleRate) * parseInt(momaPerBlock)
    );

    let bobInfo = await compoundFarm.userInfo(bob.address);
    expect(parseInt(bobInfo.shares)).to.be.equal(parseInt(bobMomaBeforeBalance));
    expect(parseInt(bobInfo.momaAtLastUserAction)).to.be.equal(parseInt(bobMomaBeforeBalance));

    let jackInfo = await compoundFarm.userInfo(jack.address);
    expect(parseInt(jackInfo.shares)).to.be.equal(parseInt(jackMomaBeforeBalance));
    expect(parseInt(jackInfo.momaAtLastUserAction)).to.be.equal(parseInt(jackMomaBeforeBalance));

    expect(parseInt(await compoundFarm.totalShares())).to.be.equal(
      parseInt(bobMomaBeforeBalance) + parseInt(jackMomaBeforeBalance)
    );
  });

  it('Bob deposits first time successfully, second time', async () => {
    await moma.connect(deployer).mint(bob.address, (2 * parseInt(bobMomaBeforeBalance)).toString());
    await moma
      .connect(bob)
      .approve(compoundFarm.address, (2 * parseInt(bobMomaBeforeBalance)).toString());

    await compoundFarm.connect(bob).deposit(bobMomaBeforeBalance);
    await time.advanceBlockTo(startBlock + 10);

    let beforePendingReward = parseInt(await momaFarm.pendingMoma(compoundFarm.address));
    expect(beforePendingReward).to.be.equal(10 * firstCycleRate * parseInt(momaPerBlock));

    await compoundFarm.connect(bob).deposit(bobMomaBeforeBalance);

    expect(parseInt(await compoundFarm.balanceOf())).to.be.equal(
      2 * parseInt(bobMomaBeforeBalance) +
        beforePendingReward +
        parseInt(firstCycleRate) * parseInt(momaPerBlock)
    );

    let bobInfo = await compoundFarm.userInfo(bob.address);
    expect(parseInt(bobInfo.shares)).to.be.equal(2 * parseInt(bobMomaBeforeBalance));
    expect(parseInt(bobInfo.momaAtLastUserAction)).to.be.equal(2 * parseInt(bobMomaBeforeBalance));

    expect(parseInt(await compoundFarm.totalShares())).to.be.equal(
      2 * parseInt(bobMomaBeforeBalance)
    );
  });

  it('Bob deposit successfully before startBlock comes, Jack deposit successfully at startBlock + 10, Alice harvest', async () => {
    await moma.connect(deployer).mint(bob.address, bobMomaBeforeBalance);
    await moma.connect(bob).approve(compoundFarm.address, bobMomaBeforeBalance);

    await moma.connect(deployer).mint(jack.address, jackMomaBeforeBalance);
    await moma.connect(jack).approve(compoundFarm.address, jackMomaBeforeBalance);

    await compoundFarm.connect(bob).deposit(bobMomaBeforeBalance);
    await time.advanceBlockTo(startBlock + 10);

    await compoundFarm.connect(jack).deposit(jackMomaBeforeBalance);
    await time.advanceBlockTo(startBlock + 20);

    let accHarvestReward = parseInt(await compoundFarm.calculateHarvestMomaRewards());
    await compoundFarm.connect(alice).harvest();

    expect(parseInt(await moma.balanceOf(alice.address))).to.be.gt(accHarvestReward);
  });

  it('Bob deposit successfully before startBlock comes, Jack deposit successfully at startBlock + 10', async () => {
    await moma.connect(deployer).mint(bob.address, bobMomaBeforeBalance);
    await moma.connect(bob).approve(compoundFarm.address, bobMomaBeforeBalance);

    await moma.connect(deployer).mint(jack.address, jackMomaBeforeBalance);
    await moma.connect(jack).approve(compoundFarm.address, jackMomaBeforeBalance);

    await compoundFarm.connect(bob).deposit(bobMomaBeforeBalance);
    await time.advanceBlockTo(startBlock + 10);

    await compoundFarm.connect(jack).deposit(jackMomaBeforeBalance);
    await time.advanceBlockTo(startBlock + 20);

    await compoundFarm.connect(bob).withdrawAll();
    console.log(parseInt(await moma.balanceOf(bob.address)));

    await compoundFarm.connect(jack).withdrawAll();
    console.log(parseInt(await moma.balanceOf(jack.address)));
  });
});
