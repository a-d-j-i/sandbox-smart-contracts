import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts} = hre;
  const {deploy} = deployments;

  const {deployer} = await getNamedAccounts();
  await deploy('MockERC1155MarketPlace3', {
    from: deployer,
    contract:
      '@sandbox-smart-contracts/dependency-operator-filter/contracts/mock/MockMarketPlace3.sol:MockERC1155MarketPlace3',
    log: true,
  });
};
export default func;
func.tags = ['MockERC1155MarketPlace3'];
