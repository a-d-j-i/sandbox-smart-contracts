import {DeployFunction} from 'hardhat-deploy/types';
import {HardhatRuntimeEnvironment} from 'hardhat/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts} = hre;
  const {deploy} = deployments;

  const {deployer} = await getNamedAccounts();

  await deploy('EndpointV2', {
    from: deployer,
    contract: 'EndpointMock',
    args: [1],
    log: true,
    skipIfAlreadyDeployed: true,
  });
};
export default func;
func.tags = ['EndpointV2', 'EndpointV2_deploy'];
