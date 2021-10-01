import {deployments, ethers} from 'hardhat';
import {Address} from 'hardhat-deploy/types';
import {BigNumber, Contract} from 'ethers';
import {gemsAndCatalystsFixtures} from '../../../common/fixtures/gemAndCatalysts';
import {assetAttributesRegistryFixture} from '../../../common/fixtures/assetAttributesRegistry';
import {assetUpgraderFixtures} from '../../../common/fixtures/assetUpgrader';

export interface MintOptions {
  from: Address;
  packId: BigNumber;
  metaDataHash: string;
  catalystId: number;
  gemIds: number[];
  quantity: number;
  rarity: number;
  to: Address;
  data: Buffer;
}

export interface MintMultiOptions {
  from: Address;
  packId: BigNumber;
  metadataHash: string;
  gemsQuantities: number[];
  catalystsQuantities: number[];
  assets: AssetData[];
  to: Address;
  data: Buffer;
}

interface AssetData {
  gemIds: number[];
  quantity: number;
  catalystId: number;
}

export const setupAssetMinter = deployments.createFixture(async () => {
  await deployments.fixture(undefined, {keepExistingDeployments: false});
  const assetMinterContract: Contract = await ethers.getContract('AssetMinter');
  const assetContract: Contract = await ethers.getContract('Asset');

  return {
    assetMinterContract,
    assetContract,
  };
});

export const setupGemsAndCatalysts = deployments.createFixture(
  gemsAndCatalystsFixtures
);

export const setupAssetAttributesRegistry = deployments.createFixture(
  assetAttributesRegistryFixture
);

export const setupAssetUpgrader = deployments.createFixture(
  assetUpgraderFixtures
);
