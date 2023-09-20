import {DeployFunction} from 'hardhat-deploy/types';
import {HardhatRuntimeEnvironment} from 'hardhat/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts} = hre;
  const {execute, catchUnknownSigner, log} = deployments;
  const {catalystMinter} = await getNamedAccounts();

  // TODO Clarify whether the below is the correct contract name
  const GiveawayContract = await deployments.get('MultiGiveawayV1');

  // TODO Specify amounts
  const amounts = {
    Common: 100,
    Uncommon: 200,
    Rare: 300,
    Epic: 400,
    Legendary: 500,
    Mythic: 600,
  };
  await catchUnknownSigner(
    execute(
      'Catalyst',
      {from: catalystMinter, log: true},
      'mintBatch',
      GiveawayContract.address,
      [1, 2, 3, 4, 5, 6],
      [
        amounts.Common,
        amounts.Uncommon,
        amounts.Rare,
        amounts.Epic,
        amounts.Legendary,
        amounts.Mythic,
      ]
    )
  );
  log(`Minted 6 NFTs to ${GiveawayContract.address}`);
};

export default func;
func.tags = ['Catalyst_mint', 'L2'];
func.dependencies = ['Catalyst_deploy'];
