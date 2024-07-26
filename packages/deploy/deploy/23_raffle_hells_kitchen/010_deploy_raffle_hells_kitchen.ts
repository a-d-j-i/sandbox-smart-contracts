import {DeployFunction} from 'hardhat-deploy/types';
import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DEPLOY_TAGS} from '../../hardhat.config';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts} = hre;
  const {deploy} = deployments;

  const {
    deployer,
    upgradeAdmin,
    treasury,
    raffleSignWallet,
    defaultOperatorFiltererRegistry,
    defaultOperatorFiltererSubscription,
  } = await getNamedAccounts();

  const TRUSTED_FORWARDER = await deployments.get('TRUSTED_FORWARDER_V2');

  let metadataUrl;
  if (hre.network.name === 'polygon') {
    metadataUrl = 'https://contracts.sandbox.game/hells-kitchen-unrevealed/';
  } else {
    metadataUrl =
      'https://contracts-demo.sandbox.game/hells-kitchen-unrevealed/';
  }

  await deploy('HellsKitchen', {
    from: deployer,
    contract: 'HellsKitchen',
    proxy: {
      owner: upgradeAdmin,
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        methodName: 'initialize',
        args: [
          metadataUrl,
          'HellsKitchen',
          'HK',
          treasury,
          raffleSignWallet,
          TRUSTED_FORWARDER.address,
          defaultOperatorFiltererRegistry,
          defaultOperatorFiltererSubscription,
          true, // we want to subscribe to OpenSea's list
        ],
      },
      upgradeIndex: 0,
    },
    log: true,
    skipIfAlreadyDeployed: true,
  });
};

export default func;
func.tags = [
  'HellsKitchen',
  'HellsKitchen_deploy',
  DEPLOY_TAGS.L2,
  DEPLOY_TAGS.L2_PROD,
  DEPLOY_TAGS.L2_TEST,
];
func.dependencies = ['TRUSTED_FORWARDER_V2'];
