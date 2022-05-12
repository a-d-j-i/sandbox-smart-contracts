import {setupL1EstateAndLand} from './fixtures';
import {ethers} from 'ethers';
import {expect} from '../chai-setup';

describe('Estate test with maps on layer 1', function () {
  describe('create one estate', function () {
    // eslint-disable-next-line mocha/no-setup-in-describe
    [24, 12, 6, 3, 1].forEach((size) => {
      it(`create one ${size}x${size} quad and create an estate with that`, async function () {
        const {
          other,
          landContractAsOther,
          estateContract,
          mintQuad,
          createEstate,
        } = await setupL1EstateAndLand();

        const quadId = await mintQuad(other, size, 48, 96);
        await landContractAsOther.setApprovalForAllFor(
          other,
          estateContract.address,
          quadId
        );
        const {gasUsed} = await createEstate([size], [48], [96]);
        console.log(
          `create one ${size}x${size} quads and create an estate with that, GAS USED: `,
          gasUsed.toString()
        );
      });
    });
  });
  describe('create a lot of states', function () {
    describe('start with 24x24', function () {
      // eslint-disable-next-line mocha/no-setup-in-describe
      [
        [576, 1],
        [4, 12],
        [16, 6],
        [256, 3],
      ].forEach(([cant, size]) => {
        it(`@slow create ${cant} 1x1 quads then create an ${size}x${size} estate with that`, async function () {
          const {
            other,
            landContractAsOther,
            estateContract,
            mintQuad,
            createEstate,
            getXsYsSizes,
          } = await setupL1EstateAndLand();
          const quadId = await mintQuad(other, 24, 0, 0);
          await landContractAsOther.setApprovalForAllFor(
            other,
            estateContract.address,
            quadId
          );
          const {xs, ys, sizes} = getXsYsSizes(0, 0, size);
          const {gasUsed} = await createEstate(sizes, xs, ys);
          console.log(
            `create ${cant} quads and ${size}x${size} estate with that, GAS USED: `,
            gasUsed.toString()
          );
        });
      });
    });
  });
  describe('create one estate and update it', function () {
    // eslint-disable-next-line mocha/no-setup-in-describe
    [24, 12, 6, 3, 1].forEach((size) => {
      it(`create an estate with ${size}x${size} quad and update it with a new quad`, async function () {
        const {
          other,
          landContractAsOther,
          estateContract,
          mintQuad,
          createEstate,
          updateEstate,
        } = await setupL1EstateAndLand();

        const quadId = await mintQuad(other, size, 48, 96);
        await landContractAsOther.setApprovalForAllFor(
          other,
          estateContract.address,
          quadId
        );
        const {estateId} = await createEstate([size], [48], [96]);

        //mint lands for update
        await mintQuad(other, size, 144, 144);
        const {gasUsed} = await updateEstate(
          [size],
          [144],
          [144],
          [size],
          [48],
          [96],
          estateId
        );
        console.log(
          `update ${size}x${size} quads, GAS USED: `,
          gasUsed.toString()
        );
      });
    });
  });
  it('tunnel message size', async function () {
    const {
      other,
      landContractAsOther,
      estateContract,
      estateTunnel,
      mintQuad,
      createEstate,
    } = await setupL1EstateAndLand();
    const quads = [
      [24, 0, 0],
      [24, 24, 0],
      [24, 0, 24],
      [6, 24, 24],
      [6, 30, 24],
      [6, 24, 30],
      [6, 30, 30],
    ];
    const sizes = [];
    const xs = [];
    const ys = [];
    for (const [size, x, y] of quads) {
      const quadId = await mintQuad(other, size, x, y);
      await landContractAsOther.setApprovalForAllFor(
        other,
        estateContract.address,
        quadId
      );
      sizes.push(size);
      xs.push(x);
      ys.push(y);
    }
    const {estateId} = await createEstate(sizes, xs, ys);
    const message = await estateTunnel.getMessage(other, estateId);
    // TODO: Check what happen when message.length > 1024.... it fails ?
    expect(ethers.utils.arrayify(message).length).to.be.equal(480);
  });
  // describe('update states', function () {
  // });
});