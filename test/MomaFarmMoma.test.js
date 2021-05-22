const { ethers } = require('hardhat');
const { expect } = require('chai');
const { time } = require('@openzeppelin/test-helpers');

describe.only('Test Moma Farming', async () => {
  let moma, momaFarm, momaVault;
  let deployer, alice, bob, jack;
  let startBlock;

  let bobMomaBeforeBalance = '1000000000000000000';
  let jackMomaBeforeBalance = '1000000000000000000';

  let amountToFarm = '2000000000000000000000000';
  let momaPerBlock = '2000000000000000000';

  beforeEach(async () => {
    [deployer, alice, bob, jack] = await ethers.getSigners();
    console.log('\n\n');

    let TestERC20 = await ethers.getContractFactory('TestERC20');
    moma = await TestERC20.connect(deployer).deploy('MOchi MArket Token', 'MOMA');

    let MomaFarm = await ethers.getContractFactory('MomaFarmMoma');
    momaFarm = await MomaFarm.connect(deployer).deploy();

    let MomaVault = await ethers.getContractFactory('MomaVault');
    momaVault = await MomaVault.connect(deployer).deploy(moma.address, momaFarm.address);

    startBlock = parseInt(await time.latestBlock()) + 100;

    await momaFarm.connect(deployer).initialize(momaVault.address, momaPerBlock, startBlock);

    await moma.connect(deployer).mint(deployer.address, amountToFarm);
    await moma.connect(deployer).approve(momaVault.address, amountToFarm);
    await momaVault.connect(deployer).depositFunds(amountToFarm);
  });

  it('All setup successfully', async () => {
    expect(await momaFarm.moma()).to.be.equal(moma.address);
    expect(await momaFarm.momaVault()).to.be.equal(momaVault.address);
    expect(parseInt(await momaFarm.startBlock())).to.be.equal(startBlock);
    expect(parseInt(await momaFarm.momaPerBlock())).to.be.equal(parseInt(momaPerBlock));
    expect(parseInt(await momaFarm.accMomaPerShare())).to.be.equal(0);
  });

  it.only('Bob deposits and withdraws before startBlock', async () => {
    let bobPendingMoma, block;
    await moma.connect(deployer).mint(bob.address, bobMomaBeforeBalance);
    await moma.connect(bob).approve(momaFarm.address, bobMomaBeforeBalance);
    await momaFarm.connect(bob).deposit(bobMomaBeforeBalance);
    block = parseInt(await time.latestBlock());
    console.log(`Bob deposit ${bobMomaBeforeBalance} at startBlock`);

    bobPendingMoma = parseInt(await momaFarm.pendingMoma(bob.address));
    expect(bobPendingMoma).to.be.equal(parseInt(bobMomaBeforeBalance));
    block = parseInt(await time.latestBlock());
    console.log(`At startBlock Bob pendingMoma: `, bobPendingMoma);

    await time.advanceBlockTo(startBlock + 2);
    block = parseInt(await time.latestBlock());

    bobPendingMoma = parseInt(await momaFarm.pendingMoma(bob.address));
    expect(bobPendingMoma).to.be.equal(parseInt(bobMomaBeforeBalance) + 2 * parseInt(momaPerBlock));
    console.log(`At (startBlock + 2) Bob pendingMoma: `, bobPendingMoma);
  });

  it('Bob and Jack deposit and withdraw before startBlock', async () => {
    await moma.connect(deployer).mint(bob.address, bobMomaBeforeBalance);
    await moma.connect(bob).approve(momaFarm.address, bobMomaBeforeBalance);

    await moma.connect(deployer).mint(jack.address, jackMomaBeforeBalance);
    await moma.connect(jack).approve(momaFarm.address, jackMomaBeforeBalance);

    await momaFarm.connect(bob).deposit(bobMomaBeforeBalance);
    await time.advanceBlockTo(startBlock + 2);

    await momaFarm.connect(jack).deposit(jackMomaBeforeBalance);

    expect(parseInt(await momaFarm.pendingMoma(bob.address))).to.be.equal(
      parseInt(bobMomaBeforeBalance) + 3 * parseInt(momaPerBlock)
    );

    expect(parseInt(await momaFarm.pendingMoma(jack.address))).to.be.equal(
      parseInt(jackMomaBeforeBalance)
    );

    console.log(parseInt(await momaFarm.pendingMoma(bob.address)));
    console.log(parseInt(await momaFarm.pendingMoma(jack.address)));
  });

  it('Bob deposits before startBlock', async () => {
    await moma.connect(deployer).mint(bob.address, bobMomaBeforeBalance);
    await moma.connect(bob).approve(momaFarm.address, bobMomaBeforeBalance);
    await momaFarm.connect(bob).deposit(bobMomaBeforeBalance);

    expect(parseInt(await momaFarm.balanceOf(bob.address))).to.be.equal(
      parseInt(bobMomaBeforeBalance)
    );

    await time.advanceBlockTo(startBlock + 1);

    expect(parseInt(await momaFarm.balanceOf(bob.address))).to.be.equal(
      parseInt(bobMomaBeforeBalance) + parseInt(momaPerBlock)
    );

    await time.advanceBlockTo(startBlock + 10);

    expect(parseInt(await momaFarm.balanceOf(bob.address))).to.be.equal(
      parseInt(bobMomaBeforeBalance) + parseInt(momaPerBlock) * 10
    );
  });

  it('Bob deposits before startBlock', async () => {
    await moma.connect(deployer).mint(bob.address, bobMomaBeforeBalance);
    await moma.connect(bob).approve(momaFarm.address, bobMomaBeforeBalance);
    await momaFarm.connect(bob).deposit(bobMomaBeforeBalance);

    await time.advanceBlockTo(startBlock + 1);

    expect(parseInt(await momaFarm.balanceOf(bob.address))).to.be.equal(
      parseInt(bobMomaBeforeBalance) + parseInt(momaPerBlock)
    );

    await time.advanceBlockTo(startBlock + 10);

    expect(parseInt(await momaFarm.balanceOf(bob.address))).to.be.equal(
      parseInt(bobMomaBeforeBalance) + parseInt(momaPerBlock) * 10
    );
  });

  it('Bob and Jack deposit before startBlock', async () => {
    let snapshotBalance;
    await moma.connect(deployer).mint(bob.address, bobMomaBeforeBalance);
    await moma.connect(bob).approve(momaFarm.address, bobMomaBeforeBalance);
    await momaFarm.connect(bob).deposit(bobMomaBeforeBalance);

    await moma.connect(deployer).mint(jack.address, jackMomaBeforeBalance);
    await moma.connect(jack).approve(momaFarm.address, jackMomaBeforeBalance);
    await momaFarm.connect(jack).deposit(jackMomaBeforeBalance);

    snapshotBalance = await momaFarm.snapshotBalance();

    await time.advanceBlockTo(startBlock + 1);

    expect(parseInt(await momaFarm.balanceOf(bob.address))).to.be.equal(
      parseInt(bobMomaBeforeBalance) +
        (parseInt(momaPerBlock) * parseInt(bobMomaBeforeBalance)) /
          parseInt(snapshotBalance[snapshotBalance.length - 1])
    );

    expect(parseInt(await momaFarm.balanceOf(jack.address))).to.be.equal(
      parseInt(jackMomaBeforeBalance) +
        (parseInt(momaPerBlock) * parseInt(jackMomaBeforeBalance)) /
          parseInt(snapshotBalance[snapshotBalance.length - 1])
    );

    await time.advanceBlockTo(startBlock + 10);

    expect(parseInt(await momaFarm.balanceOf(bob.address))).to.be.equal(
      parseInt(bobMomaBeforeBalance) +
        (10 * parseInt(momaPerBlock) * parseInt(bobMomaBeforeBalance)) /
          parseInt(snapshotBalance[snapshotBalance.length - 1])
    );

    expect(parseInt(await momaFarm.balanceOf(jack.address))).to.be.equal(
      parseInt(jackMomaBeforeBalance) +
        (10 * parseInt(momaPerBlock) * parseInt(jackMomaBeforeBalance)) /
          parseInt(snapshotBalance[snapshotBalance.length - 1])
    );
  });

  it('Bob deposits before startBlock and Jack deposits after startBlock', async () => {
    await moma.connect(deployer).mint(bob.address, bobMomaBeforeBalance);
    await moma.connect(bob).approve(momaFarm.address, bobMomaBeforeBalance);

    await moma.connect(deployer).mint(jack.address, jackMomaBeforeBalance);
    await moma.connect(jack).approve(momaFarm.address, jackMomaBeforeBalance);

    await momaFarm.connect(bob).deposit(bobMomaBeforeBalance);

    await time.advanceBlockTo(startBlock + 10);

    await momaFarm.connect(jack).deposit(jackMomaBeforeBalance);

    let snapshotBalance = await momaFarm.snapshotBalance();
    expect(snapshotBalance.length).to.be.equal(2);

    let totalInFarm = snapshotBalance[1];
    expect(parseInt(totalInFarm)).to.be.equal(parseInt(await moma.balanceOf(momaFarm.address)));
    expect(parseInt(totalInFarm)).to.be.equal(
      parseInt(bobMomaBeforeBalance) + parseInt(jackMomaBeforeBalance) + 11 * parseInt(momaPerBlock)
    );

    let bobBeforeBalance = await momaFarm.balanceOf(bob.address);
    expect(parseInt(bobBeforeBalance)).to.be.equal(
      parseInt(bobMomaBeforeBalance) + 11 * parseInt(momaPerBlock)
    );

    let jackBeforeBalance = await momaFarm.balanceOf(jack.address);

    expect(parseInt(jackBeforeBalance)).to.be.equal(parseInt(jackMomaBeforeBalance));

    await time.advanceBlockTo(startBlock + 20);

    expect(parseInt(await momaFarm.balanceOf(bob.address))).to.be.equal(
      parseInt(bobBeforeBalance) +
        (parseInt(bobBeforeBalance) * parseInt(momaPerBlock) * 9) / parseInt(totalInFarm)
    );

    expect(parseInt(await momaFarm.balanceOf(jack.address))).to.be.equal(
      parseInt(jackBeforeBalance) +
        (parseInt(jackBeforeBalance) * parseInt(momaPerBlock) * 9) / parseInt(totalInFarm)
    );
  });
});
