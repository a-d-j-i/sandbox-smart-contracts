import { expect } from "chai";
import { expectEventWithArgs } from "../util";
import { ethers } from "hardhat";
import { runAssetSetup } from "./fixtures/assetFixture"


// TODO: test all events
// TODO: test all reverts
// TODO: trustedForwarder tests
// TODO: missing setTrustedForwarder default admin function
// TODO: tokenId tests (TokenIdUtils.sol)
describe("AssetContract", () => {
  it("Should deploy correctly", async () => {
    const { AssetContract } = await runAssetSetup();
    expect(AssetContract.address).to.be.properAddress;
  });

  describe("uri_and_baseUri", () => {
    it("Should return correct asset uri ", async () => {
      const { AssetContractAsMinter, AssetContract, owner, uris, baseUri } = await runAssetSetup();
      const tnx = await AssetContractAsMinter.mint(owner, 10, 3, uris[0]);
      const args = await expectEventWithArgs(
        AssetContractAsMinter,
        tnx,
        "TransferSingle"
      );
      const tokenId = args.args.id;
      expect(await AssetContract.uri(tokenId)).to.be.equal(
        `${baseUri}${uris[0]}`
      );
    });

    it("DEFAULT_ADMIN can change an asset's uri ", async () => {
      const { AssetContractAsMinter, AssetContract, AssetContractAsAdmin, owner, uris, baseUri } = await runAssetSetup();
      const tnx = await AssetContractAsMinter.mint(owner, 10, 3, uris[0]);
      const args = await expectEventWithArgs(
        AssetContractAsMinter,
        tnx,
        "TransferSingle"
      );
      const tokenId = args.args.id;
      expect(await AssetContract.uri(tokenId)).to.be.equal(
        `${baseUri}${uris[0]}`
      );

      await AssetContractAsAdmin.setTokenUri(tokenId, uris[1]);
      expect(await AssetContract.uri(tokenId)).to.be.equal(
        `${baseUri}${uris[1]}`
      );
    });


    it("DEFAULT_ADMIN can change the contract's base uri ", async () => {
      const { AssetContractAsAdmin, AssetContract } = await runAssetSetup();
      await AssetContractAsAdmin.setBaseURI('newUri')
      expect(await AssetContract.baseUri).to.not.be.reverted;
    });

    it("if not DEFAULT_ADMIN cannot change an asset uri ", async () => {
      const { AssetContractAsMinter, AssetContract, AssetContractAsOwner, owner, uris, baseUri, defaultAdminRole } = await runAssetSetup();
      const tnx = await AssetContractAsMinter.mint(owner, 10, 3, uris[0]);
      const args = await expectEventWithArgs(
        AssetContractAsMinter,
        tnx,
        "TransferSingle"
      );
      const tokenId = args.args.id;
      expect(await AssetContract.uri(tokenId)).to.be.equal(
        `${baseUri}${uris[0]}`
      );
      await expect(AssetContractAsOwner.setTokenUri(tokenId, uris[2])).to.be.revertedWith(`AccessControl: account ${owner.toLocaleLowerCase()} is missing role ${defaultAdminRole}`);
      expect(await AssetContract.uri(tokenId)).to.be.equal(
        `${baseUri}${uris[0]}`
      );
    });

    it("if not DEFAULT_ADMIN cannot change the contract's base uri ", async () => {
      const { AssetContractAsOwner, owner, defaultAdminRole } = await runAssetSetup();
      await expect(
        AssetContractAsOwner.setBaseURI('newUri')
      ).to.be.revertedWith(`AccessControl: account ${owner.toLocaleLowerCase()} is missing role ${defaultAdminRole}`);
    });

    it("no two asset can have same uri ", async () => {
      const { AssetContractAsMinter, owner, uris} = await runAssetSetup();
      await AssetContractAsMinter.mint(owner, 10, 3, uris[0]);

      await expect(
        AssetContractAsMinter.mint(owner, 11, 3, uris[0])
      ).to.be.revertedWith("metadata hash mismatch for tokenId");
    });
  });

  describe("Minting", () => {
    it("Should mint an asset", async () => {
      const { AssetContractAsMinter, AssetContract, owner, uris } = await runAssetSetup();
      const tnx = await AssetContractAsMinter.mint(owner, 10, 3, uris[0]);
      const args = await expectEventWithArgs(
        AssetContractAsMinter,
        tnx,
        "TransferSingle"
      );
      const tokenId = args.args.id;
      expect(await AssetContract.balanceOf(owner, tokenId)).to.be.equal(3);
    });

    it("only minter can mint an asset", async () => {
      const { AssetContract, owner, minterRole, uris } = await runAssetSetup();
      await expect(
        AssetContract.connect(await ethers.provider.getSigner(owner)).mint(
          owner, 10, 3,
          uris[0]
        )
      ).to.be.revertedWith(
        `AccessControl: account ${owner.toLocaleLowerCase()} is missing role ${minterRole}`
      );
    });

    it("Should mint Batch assets", async () => {
      const { AssetContractAsMinter, AssetContract, owner } = await runAssetSetup();
      const tnx = await AssetContractAsMinter.mintBatch(
        owner,
        [1, 2, 3, 4],
        [5, 5, 100, 1],
        ["xyz", "abc", "anotherUri", "andAgain"]
      );
      const args = await expectEventWithArgs(
        AssetContractAsMinter,
        tnx,
        "TransferBatch"
      );
      const tokenIds = args.args.ids;
      expect(tokenIds[0]).to.be.equal(1);
      expect(tokenIds[1]).to.be.equal(2);
      expect(tokenIds[2]).to.be.equal(3);
      expect(tokenIds[3]).to.be.equal(4);
      expect(await AssetContract.balanceOf(owner, 1)).to.be.equal(5);
      expect(await AssetContract.balanceOf(owner, 2)).to.be.equal(5);
      expect(await AssetContract.balanceOf(owner, 3)).to.be.equal(100);
      expect(await AssetContract.balanceOf(owner, 4)).to.be.equal(1);
    });

    it("only minter can mint batch an asset", async () => {
      const { AssetContract, owner, minterRole } = await runAssetSetup();
      await expect(
        AssetContract.connect(await ethers.provider.getSigner(owner)).mintBatch(
          owner,
        [1, 2, 3, 4],
        [5, 5, 100, 1],
        ["xyz", "abc", "anotherUri", "andAgain"]
        )
      ).to.be.revertedWith(
        `AccessControl: account ${owner.toLocaleLowerCase()} is missing role ${minterRole}`
      );
    });
  });

  describe("Burn Assets", () => {
    it("BURNER_ROLE can use burnFrom to burn the asset of any owner", async () => {
      const { AssetContractAsMinter, AssetContractAsBurner, AssetContract, owner, uris } = await runAssetSetup();
      const tnx = await AssetContractAsMinter.mint(owner, 10, 3, uris[0]);
      const args = await expectEventWithArgs(
        AssetContractAsMinter,
        tnx,
        "TransferSingle"
      );
      const tokenId = args.args.id;
      expect(tokenId).to.be.equal(10);
      expect(await AssetContract.balanceOf(owner, tokenId)).to.be.equal(3);
      await AssetContractAsBurner.burnFrom(owner, tokenId, 2);
      expect(await AssetContract.balanceOf(owner, tokenId)).to.be.equal(1);
    });

    it("If not BURNER_ROLE cannot burn asset of any owner", async () => {
      const { AssetContractAsMinter, owner, AssetContract, secondOwner, burnerRole, uris } =
        await runAssetSetup();
      const tnx = await AssetContractAsMinter.mint(owner, 10, 3, uris[0]);
      const args = await expectEventWithArgs(
        AssetContractAsMinter,
        tnx,
        "TransferSingle"
      );
      const tokenId = args.args.id;
      expect(tokenId).to.be.equal(10);
      expect(await AssetContract.balanceOf(owner, tokenId)).to.be.equal(3);

      await expect(
        AssetContract.connect(await ethers.provider.getSigner(secondOwner)).burnFrom(
          owner,
          tokenId,
          3
        )
      ).to.be.revertedWith(
        `AccessControl: account ${secondOwner.toLocaleLowerCase()} is missing role ${burnerRole}`
      );
    });

    it("owner can burn their own asset", async () => {
      const { AssetContractAsMinter, owner, AssetContract, uris } = await runAssetSetup();
      const tnx = await AssetContractAsMinter.mint(owner, 10, 3, uris[0]);
      const args = await expectEventWithArgs(
        AssetContractAsMinter,
        tnx,
        "TransferSingle"
      );
      const tokenId1 = args.args.id;

      expect(await AssetContract.balanceOf(owner, tokenId1)).to.be.equal(3);

      await AssetContract.connect(await ethers.provider.getSigner(owner)).burn(
        owner,
        tokenId1,
        3
      );

      expect(await AssetContract.balanceOf(owner, tokenId1)).to.be.equal(0);
    });

    it("owner cannot burn someone else's asset", async () => {
      const { AssetContractAsMinter, owner, AssetContract, uris, secondOwner, burnerRole } = await runAssetSetup();
      const tnx = await AssetContractAsMinter.mint(owner, 10, 3, uris[0]);
      const args = await expectEventWithArgs(
        AssetContractAsMinter,
        tnx,
        "TransferSingle"
      );

      expect(await AssetContract.balanceOf(owner, 10)).to.be.equal(3);

      await expect(
        AssetContract.connect(await ethers.provider.getSigner(secondOwner)).burn(
          owner,
          10,
          3
        )
      ).to.be.revertedWith(
        `ERC1155: caller is not token owner or approved`
      );

      expect(await AssetContract.balanceOf(owner, 10)).to.be.equal(3);
    });

    it("owner can batch burn their own assets", async () => {
      const { AssetContractAsMinter, owner, AssetContract } = await runAssetSetup();
      const tnx = await AssetContractAsMinter.mintBatch(
        owner,
        [1, 2, 3, 4],
        [5, 5, 100, 1],
        ["xyz", "abc", "anotherUri", "andAgain"]
      );
      const args = await expectEventWithArgs(
        AssetContractAsMinter,
        tnx,
        "TransferBatch"
      );
      const tokenIds = args.args.ids;

      expect(await AssetContract.balanceOf(owner, tokenIds[0])).to.be.equal(5);
      expect(await AssetContract.balanceOf(owner, tokenIds[1])).to.be.equal(5);
      expect(await AssetContract.balanceOf(owner, tokenIds[2])).to.be.equal(100);
      expect(await AssetContract.balanceOf(owner, tokenIds[3])).to.be.equal(1);

      await AssetContract.connect(await ethers.provider.getSigner(owner)).burnBatch(
        owner,
        [1, 2, 3, 4],
        [4, 4, 20, 1]
      );

      expect(await AssetContract.balanceOf(owner, tokenIds[0])).to.be.equal(1);
      expect(await AssetContract.balanceOf(owner, tokenIds[1])).to.be.equal(1);
      expect(await AssetContract.balanceOf(owner, tokenIds[2])).to.be.equal(80);
      expect(await AssetContract.balanceOf(owner, tokenIds[3])).to.be.equal(0);
    });

    it("owner cannot batch burn someone else's assets", async () => {
      const { AssetContractAsMinter, owner, AssetContract, secondOwner, burnerRole } = await runAssetSetup();
      const tnx = await AssetContractAsMinter.mintBatch(
        owner,
        [1, 2, 3, 4],
        [5, 5, 100, 1],
        ["xyz", "abc", "anotherUri", "andAgain"]
      );
    
      await expect(
        AssetContract.connect(await ethers.provider.getSigner(secondOwner)).burn(
          owner,
        [1, 2, 3, 4],
        [5, 5, 100, 1],
        )
      ).to.be.revertedWith(
        `ERC1155: caller is not token owner or approved`
      );

      expect(await AssetContract.balanceOf(owner, 1)).to.be.equal(5);
      expect(await AssetContract.balanceOf(owner, 2)).to.be.equal(5);
      expect(await AssetContract.balanceOf(owner, 3)).to.be.equal(100);
      expect(await AssetContract.balanceOf(owner, 4)).to.be.equal(1);
    });

    it("BURNER_ROLE can batch burn the assets of any owner", async () => {
      const { AssetContractAsMinter, AssetContractAsBurner, owner, AssetContract } = await runAssetSetup();
      const tnx = await AssetContractAsMinter.mintBatch(
        owner,
        [1, 2, 3, 4],
        [5, 5, 100, 1],
        ["xyz", "abc", "anotherUri", "andAgain"]
      );
      const args = await expectEventWithArgs(
        AssetContractAsMinter,
        tnx,
        "TransferBatch"
      );
      const tokenIds = args.args.ids;

      expect(await AssetContract.balanceOf(owner, tokenIds[0])).to.be.equal(5);
      expect(await AssetContract.balanceOf(owner, tokenIds[1])).to.be.equal(5);
      expect(await AssetContract.balanceOf(owner, tokenIds[2])).to.be.equal(100);
      expect(await AssetContract.balanceOf(owner, tokenIds[3])).to.be.equal(1);

      await AssetContractAsBurner.burnBatchFrom(
        owner,
        [1, 2, 3, 4],
        [4, 4, 20, 1]
      );

      expect(await AssetContract.balanceOf(owner, tokenIds[0])).to.be.equal(1);
      expect(await AssetContract.balanceOf(owner, tokenIds[1])).to.be.equal(1);
      expect(await AssetContract.balanceOf(owner, tokenIds[2])).to.be.equal(80);
      expect(await AssetContract.balanceOf(owner, tokenIds[3])).to.be.equal(0);
    });

    it("If not BURNER_ROLE cannot batch burn assets of any owner", async () => {
      const { AssetContractAsMinter, owner, AssetContract, secondOwner, burnerRole, uris } =
        await runAssetSetup();
      const tnx = await AssetContractAsMinter.mint(owner, 10, 3, uris[0]);
      const args = await expectEventWithArgs(
        AssetContractAsMinter,
        tnx,
        "TransferSingle"
      );
      const tokenId = args.args.id;
      expect(tokenId).to.be.equal(10);
      expect(await AssetContract.balanceOf(owner, tokenId)).to.be.equal(3);

      await expect(
        AssetContract.connect(await ethers.provider.getSigner(secondOwner)).burnFrom(
          owner,
          tokenId,
          3
        )
      ).to.be.revertedWith(
        `AccessControl: account ${secondOwner.toLocaleLowerCase()} is missing role ${burnerRole}`
      );
    });
  });

  describe("Token transfer", () => {
    it("owner can transfer an asset", async () => {
      const { AssetContractAsMinter, owner, AssetContract, secondOwner, uris } =
        await runAssetSetup();
      const tnx = await AssetContractAsMinter.mint(owner, 10, 5, uris[0]);
      const args = await expectEventWithArgs(
        AssetContract,
        tnx,
        "TransferSingle"
      );
      const tokenId1 = args.args.id;

      expect(await AssetContract.balanceOf(owner, tokenId1)).to.be.equal(5);

      await AssetContract.connect(
        await ethers.provider.getSigner(owner)
      ).safeTransferFrom(owner, secondOwner, tokenId1, 5, "0x");

      expect(await AssetContract.balanceOf(secondOwner, tokenId1)).to.be.equal(
        5
      );
    });

    it("owner can batch transfer assets", async () => {
      const { AssetContractAsMinter, owner, AssetContract, secondOwner} =
        await runAssetSetup();
        const tnx = await AssetContractAsMinter.mintBatch(
          owner,
          [1, 2, 3, 4],
          [5, 5, 100, 1],
          ["xyz", "abc", "anotherUri", "andAgain"]
        );
      const args = await expectEventWithArgs(
        AssetContract,
        tnx,
        "TransferBatch"
      );
      const tokenIds = args.args.ids;

      expect(await AssetContract.balanceOf(owner, tokenIds[0])).to.be.equal(5);
      expect(await AssetContract.balanceOf(owner, tokenIds[1])).to.be.equal(5);
      expect(await AssetContract.balanceOf(owner, tokenIds[2])).to.be.equal(100);
      expect(await AssetContract.balanceOf(owner, tokenIds[3])).to.be.equal(1);

      await AssetContract.connect(
        await ethers.provider.getSigner(owner)
      ).safeBatchTransferFrom(
        owner,
        secondOwner,
        [tokenIds[0], tokenIds[1]],
        [5, 5],
        "0x"
      );

      expect(
        await AssetContract.balanceOf(secondOwner, tokenIds[0])
      ).to.be.equal(5);

      expect(
        await AssetContract.balanceOf(secondOwner, tokenIds[1])
      ).to.be.equal(5);

      expect(
        await AssetContract.balanceOf(owner, tokenIds[0])
      ).to.be.equal(0);

      expect(
        await AssetContract.balanceOf(owner, tokenIds[1])
      ).to.be.equal(0);
    });
  });
});
