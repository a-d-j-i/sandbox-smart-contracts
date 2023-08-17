import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts} = hre;
  const {execute, log, read, catchUnknownSigner} = deployments;
  const {assetAdmin, backendAuthWallet} = await getNamedAccounts();

  const assetReveal = await deployments.get('AssetReveal');

  const minterRole = await read('Asset', 'MINTER_ROLE');
  if (!(await read('Asset', 'hasRole', minterRole, assetReveal.address))) {
    await catchUnknownSigner(
      execute(
        'Asset',
        {from: assetAdmin, log: true},
        'grantRole',
        minterRole,
        assetReveal.address
      )
    );
    log(`Asset MINTER_ROLE granted to ${assetReveal.address}`);
  }

  const burnerRole = await read('Asset', 'BURNER_ROLE');
  if (!(await read('Asset', 'hasRole', burnerRole, assetReveal.address))) {
    await catchUnknownSigner(
      execute(
        'Asset',
        {from: assetAdmin, log: true},
        'grantRole',
        burnerRole,
        assetReveal.address
      )
    );
    log(`Asset BURNER_ROLE granted to ${assetReveal.address}`);
  }

  await catchUnknownSigner(
    execute(
      'AuthSuperValidator',
      {from: assetAdmin, log: true},
      'setSigner',
      assetReveal.address,
      backendAuthWallet
    )
  );

  log(`AuthSuperValidator signer for Asset Reveal set to ${backendAuthWallet}`);

  await catchUnknownSigner(
    execute(
      'AssetReveal',
      {from: assetAdmin, log: true},
      'setTierInstantRevealAllowed',
      5,
      true
    )
  );

  log(`Allowed instant reveal for tier 5 assets (Mythical))`);
};

export default func;

func.tags = ['Asset', 'AssetReveal_setup'];
func.dependencies = ['Asset_deploy', 'AssetCreate_deploy'];
