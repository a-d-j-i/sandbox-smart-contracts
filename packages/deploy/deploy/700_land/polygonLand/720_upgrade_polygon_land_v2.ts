import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts} = hre;
  const {deploy, catchUnknownSigner} = deployments;
  const {deployer, upgradeAdmin} = await getNamedAccounts();
  await catchUnknownSigner(
    deploy('PolygonLand', {
      from: deployer,
      contract:
        '@sandbox-smart-contracts/core/src/solc_0.8/polygon/child/land/PolygonLandV2.sol:PolygonLandV2',
      proxy: {
        owner: upgradeAdmin,
        proxyContract: 'OpenZeppelinTransparentProxy',
        upgradeIndex: 1,
      },
      log: true,
    })
  );
};
export default func;
func.tags = ['PolygonLand', 'PolygonLandV2', 'PolygonLandV2_deploy', 'L2'];
func.dependencies = ['PolygonLand_deploy'];
