import { Contract } from "@ethersproject/contracts";
import { expect } from "chai";
import { ethers } from "hardhat";
const abi = require('/Users/dperk6/qfi/qdex/artifacts/contracts/interfaces/IERC20.sol/IERC20.json');

describe("Check", function () {

  it("Should create a new wrapped token", async function () {
    const Wrapped = await ethers.getContractFactory("WrapRegistry");
    const registry = await Wrapped.deploy();
    await registry.deployed();
    const newToken = await ethers.getContractFactory("WrappedToken");
    const token = await newToken.deploy("Test", "TST", registry.address);
    await token.deployed();
    expect(await registry.createWrappedToken(token.address));
  });

  it("Should deposit a token and received wrapped", async function () {
    const Wrapped = await ethers.getContractFactory("WrapRegistry");
    const registry = await Wrapped.deploy();
    await registry.deployed();
    const newToken = await ethers.getContractFactory("WrappedToken");
    const token = await newToken.deploy("Test", "TST", registry.address);
    await token.deployed();
    await token.approve(registry.address, "1000000000000000000000");
    const pool = await registry.createWrappedToken(token.address);
    await pool.wait();
    const wrappedAddr = await registry.checkToken(token.address);
    const wrappedContr = await (new Contract(wrappedAddr, abi.abi)).deployed();
    const baseContr = await (new Contract(token.address, abi.abi)).deployed();
    const [{ address }] = await ethers.getSigners();
    /*const balance = await wrappedContr.balanceOf(address).call();
    const regBalance = await baseContr.balanceOf(registry.address).call();
    expect(balance).to.equal("1000000000000000000000");
    expect(regBalance).to.equal("1000000000000000000000");*/
  });

});
