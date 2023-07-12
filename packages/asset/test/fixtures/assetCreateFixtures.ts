import {ethers, upgrades} from 'hardhat';
import {
  createAssetMintSignature,
  createMultipleAssetsMintSignature,
} from '../utils/createSignature';
import {
  CATALYST_BASE_URI,
  CATALYST_DEFAULT_ROYALTY,
  CATALYST_IPFS_CID_PER_TIER,
} from '../../data/constants';

const name = 'Sandbox Asset Create';
const version = '1.0';

export async function runCreateTestSetup() {
  const [
    catalystMinter,
    trustedForwarder,
    assetAdmin,
    user,
    otherWallet,
    catalystRoyaltyRecipient,
    catalystAdmin,
    authValidatorAdmin,
    backendAuthWallet,
  ] = await ethers.getSigners();

  // test upgradeable contract using '@openzeppelin/hardhat-upgrades'
  // DEPLOY DEPENDENCIES: ASSET, CATALYST, AUTH VALIDATOR, OPERATOR FILTER REGISTRANT

  const OperatorFilterRegistrantFactory = await ethers.getContractFactory(
    'OperatorFilterRegistrant'
  );
  const OperatorFilterRegistrantContract =
    await OperatorFilterRegistrantFactory.deploy();

  const AssetFactory = await ethers.getContractFactory('Asset');
  const AssetContract = await upgrades.deployProxy(
    AssetFactory,
    [
      trustedForwarder.address,
      assetAdmin.address,
      [1, 2, 3, 4, 5, 6],
      [2, 4, 6, 8, 10, 12],
      'ipfs://',
      OperatorFilterRegistrantContract.address,
    ],
    {
      initializer: 'initialize',
    }
  );

  await AssetContract.deployed();

  const CatalystFactory = await ethers.getContractFactory('Catalyst');
  const CatalystContract = await upgrades.deployProxy(
    CatalystFactory,
    [
      CATALYST_BASE_URI,
      trustedForwarder.address,
      catalystRoyaltyRecipient.address,
      OperatorFilterRegistrantContract.address,
      catalystAdmin.address, // DEFAULT_ADMIN_ROLE
      catalystMinter.address, // MINTER_ROLE
      CATALYST_DEFAULT_ROYALTY,
      CATALYST_IPFS_CID_PER_TIER,
    ],
    {
      initializer: 'initialize',
    }
  );

  await CatalystContract.deployed();

  const AuthValidatorFactory = await ethers.getContractFactory('AuthValidator');
  const AuthValidatorContract = await AuthValidatorFactory.deploy(
    authValidatorAdmin.address,
    backendAuthWallet.address
  );

  // END DEPLOY DEPENDENCIES

  const AssetCreateFactory = await ethers.getContractFactory('AssetCreate');

  const AssetCreateContract = await upgrades.deployProxy(
    AssetCreateFactory,
    [
      name,
      version,
      AssetContract.address,
      CatalystContract.address,
      AuthValidatorContract.address,
      trustedForwarder.address,
      assetAdmin.address, // DEFAULT_ADMIN_ROLE
    ],
    {
      initializer: 'initialize',
    }
  );

  await AssetCreateContract.deployed();

  const AssetCreateContractAsUser = AssetCreateContract.connect(user);

  // SETUP ROLES
  // get AssetContract as DEFAULT_ADMIN_ROLE
  const AssetAsAdmin = AssetContract.connect(assetAdmin);
  const MinterRole = await AssetAsAdmin.MINTER_ROLE();
  await AssetAsAdmin.grantRole(MinterRole, AssetCreateContract.address);

  // get CatalystContract as DEFAULT_ADMIN_ROLE
  const CatalystAsAdmin = CatalystContract.connect(catalystAdmin);
  const CatalystMinterRole = await CatalystAsAdmin.MINTER_ROLE();
  await CatalystAsAdmin.grantRole(
    CatalystMinterRole,
    AssetCreateContract.address
  );

  const AssetCreateAsAdmin = AssetCreateContract.connect(assetAdmin);
  const SpecialMinterRole = await AssetCreateContract.SPECIAL_MINTER_ROLE();
  // END SETUP ROLES

  // HELPER FUNCTIONS
  const grantSpecialMinterRole = async (address: string) => {
    await AssetCreateAsAdmin.grantRole(SpecialMinterRole, address);
  };

  const mintCatalyst = async (
    tier: number,
    amount: number,
    to = user.address
  ) => {
    const signer = catalystMinter;
    await CatalystContract.connect(signer).mint(to, tier, amount);
  };

  const mintSingleAsset = async (
    signature: string,
    tier: number,
    amount: number,
    revealed: boolean,
    metadataHash: string
  ) => {
    await AssetCreateContractAsUser.createAsset(
      signature,
      tier,
      amount,
      revealed,
      metadataHash,
      user.address
    );
  };

  const mintMultipleAssets = async (
    signature: string,
    tiers: number[],
    amounts: number[],
    revealed: boolean[],
    metadataHashes: string[]
  ) => {
    await AssetCreateContractAsUser.createMultipleAssets(
      signature,
      tiers,
      amounts,
      revealed,
      metadataHashes,
      user.address
    );
  };

  const mintSpecialAsset = async (
    signature: string,
    tier: number,
    amount: number,
    revealed: boolean,
    metadataHash: string
  ) => {
    await AssetCreateContractAsUser.createSpecialAsset(
      signature,
      tier,
      amount,
      revealed,
      metadataHash,
      user.address
    );
  };

  const getCreatorNonce = async (creator: string) => {
    const nonce = await AssetCreateContract.creatorNonces(creator);
    return nonce;
  };

  const generateSingleMintSignature = async (
    creator: string,
    tier: number,
    amount: number,
    revealed: boolean,
    metadataHash: string
  ) => {
    const signature = await createAssetMintSignature(
      creator,
      tier,
      amount,
      revealed,
      metadataHash,
      AssetCreateContract,
      backendAuthWallet
    );
    return signature;
  };

  const generateMultipleMintSignature = async (
    creator: string,
    tiers: number[],
    amounts: number[],
    revealed: boolean[],
    metadataHashes: string[]
  ) => {
    const signature = await createMultipleAssetsMintSignature(
      creator,
      tiers,
      amounts,
      revealed,
      metadataHashes,
      AssetCreateContract,
      backendAuthWallet
    );
    return signature;
  };
  // END HELPER FUNCTIONS

  return {
    metadataHashes: [
      'QmZvGR5JNtSjSgSL9sD8V3LpSTHYXcfc9gy3CqptuoETJA',
      'QmcU8NLdWyoDAbPc67irYpCnCH9ciRUjMC784dvRfy1Fja',
    ],
    additionalMetadataHash: 'QmZEhV6rMsZfNyAmNKrWuN965xaidZ8r5nd2XkZq9yZ95L',
    user,
    otherWallet,
    AssetContract,
    AssetCreateContract,
    AuthValidatorContract,
    CatalystContract,
    mintCatalyst,
    mintSingleAsset,
    mintMultipleAssets,
    mintSpecialAsset,
    grantSpecialMinterRole,
    generateSingleMintSignature,
    generateMultipleMintSignature,
    getCreatorNonce,
  };
}
