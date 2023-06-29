import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const {
    deployer,
    assetAdmin,
    upgradeAdmin,
    trustedForwarder,
    commonRoyaltyReceiver,
  } = await getNamedAccounts();
  const Manager = await deployments.get("Manager");

  await deploy("Asset", {
    from: deployer,
    contract: "Asset",
    proxy: {
      owner: upgradeAdmin,
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        methodName: "initialize",
        args: [
          trustedForwarder,
          assetAdmin,
          [1, 2, 3, 4, 5, 6],
          [2, 4, 6, 8, 10, 12],
          "ipfs://",
          commonRoyaltyReceiver,
          300,
          Manager.address,
        ],
      },
      upgradeIndex: 0,
    },
    log: true,
  });
};
export default func;

func.tags = ["Asset"];
func.dependencies = ["Manager"];
