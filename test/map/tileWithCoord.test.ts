import {expect} from '../chai-setup';
import {
  printTileWithCoord,
  setupTileWithCoordsLibTest,
  tileWithCoordToJS,
} from './fixtures';
import {BigNumber} from 'ethers';

describe('TileWithCoordLib', function () {
  // eslint-disable-next-line mocha/no-skipped-tests
  it.skip('Some Tile With Coords', async function () {
    const tester = await setupTileWithCoordsLibTest();
    const x0 = 12345;
    const y0 = 54321;
    await tester.initTileWithCoord(0, x0, y0);
    // x0 % 24 == y0 % 24 == 9
    await tester.setQuad(0, x0 - 9, y0 - 9, 1);
    await tester.setQuad(0, x0 - 9 + 23, y0 - 9 + 23, 1);
    await tester.setQuad(0, x0 - 9 + 3, y0 - 9 + 0, 3);
    await tester.setQuad(0, x0 - 9 + 12, y0 - 9 + 6, 6);
    await tester.clearQuad(0, x0 - 9 + 15, y0 - 9 + 9, 3);
    const tile = await tester.getTile(0);
    const c = tileWithCoordToJS(tile);
    printTileWithCoord(c);
  });

  it('x, y, key', async function () {
    const tester = await setupTileWithCoordsLibTest();
    await tester.initTileWithCoord(0, 24 * 123, 24 * 321);
    const x = BigNumber.from(await tester.getX(0));
    expect(x).to.be.equal(123);
    const y = BigNumber.from(await tester.getY(0));
    expect(y).to.be.equal(321);
    expect(await tester.getKey(0)).to.be.equal(x.or(y.shl(32)));
  });

  it('merge', async function () {
    const tester = await setupTileWithCoordsLibTest();
    const tests = [
      [3, 0, 3],
      [12, 6, 6],
      [1, 1, 1],
      [23, 23, 1],
    ];
    const right = 24 * 123;
    const top = 24 * 321;

    // 0
    await tester.initTileWithCoord(0, right, top);
    for (const t of tests) {
      await tester.setQuad(0, right + t[0], top + t[1], t[2]);
    }
    const tile = tileWithCoordToJS(await tester.getTile(0));

    // merge
    const outIdx = 29;
    await tester.initTileWithCoord(outIdx, right, top);
    for (let idx = 0; idx < tests.length; idx++) {
      await tester.initTileWithCoord(idx + 1, right, top);
      const t = tests[idx];
      await tester.setQuad(idx + 1, right + t[0], top + t[1], t[2]);
      await tester.merge(outIdx, idx + 1);
    }
    const result = tileWithCoordToJS(await tester.getTile(outIdx));
    expect(result).to.be.eql(tile);
  });

  it('subtract', async function () {
    const tester = await setupTileWithCoordsLibTest();
    const tests = [
      [3, 0, 3],
      [12, 6, 6],
      [1, 1, 1],
      [23, 23, 1],
    ];
    const right = 24 * 123;
    const top = 24 * 321;

    // 0
    await tester.initTileWithCoord(0, right, top);
    await tester.setQuad(0, right, top, 24); // all ones
    for (const t of tests) {
      await tester.clearQuad(0, right + t[0], top + t[1], t[2]);
    }
    const tile = tileWithCoordToJS(await tester.getTile(0));

    // a lot of tiles to subtract
    for (let idx = 0; idx < tests.length; idx++) {
      await tester.initTileWithCoord(idx + 1, right, top);
      const t = tests[idx];
      await tester.setQuad(idx + 1, right + t[0], top + t[1], t[2]);
    }

    const outIdx = 29;
    await tester.initTileWithCoord(outIdx, right, top);
    await tester.setQuad(outIdx, right, top, 24); // all ones
    for (let idx = 0; idx < tests.length; idx++) {
      await tester.subtract(outIdx, idx + 1);
    }
    const result = tileWithCoordToJS(await tester.getTile(outIdx));
    expect(result).to.be.eql(tile);
  });

  it('contains', async function () {
    const tester = await setupTileWithCoordsLibTest();
    const tests = [
      [3, 0, 3],
      [12, 6, 6],
      [1, 1, 1],
      [23, 23, 1],
    ];
    const right = 24 * 123;
    const top = 24 * 321;
    // 0
    await tester.initTileWithCoord(0, right, top);
    for (const t of tests) {
      await tester.setQuad(0, right + t[0], top + t[1], t[2]);
    }
    // 1
    for (const t of tests) {
      await tester.initTileWithCoord(1, right, top);
      await tester.setQuad(1, right + t[0], top + t[1], t[2]);
      expect(await tester.containQuad(1, right + t[0], top + t[1], t[2])).to.be
        .true;
      expect(await tester.containQuad(0, right + t[0], top + t[1], t[2])).to.be
        .true;
    }
    expect(await tester.containQuad(0, right + 2, top + 2, 1)).to.be.false;
    expect(await tester.containQuad(0, right + 22, top + 22, 1)).to.be.false;
    expect(await tester.containQuad(0, right + 21, top + 21, 3)).to.be.false;
  });

  it('isEmpty', async function () {
    const tester = await setupTileWithCoordsLibTest();
    const right = 24 * 123;
    const top = 24 * 321;
    await tester.initTileWithCoord(0, right, top);
    expect(await tester.isEmpty(0)).to.be.true;
    await tester.setQuad(0, right, top, 6);
    expect(await tester.isEmpty(0)).to.be.false;
    await tester.clearQuad(0, right, top, 6);
    expect(await tester.isEmpty(0)).to.be.true;
  });

  // TODO: Add more tests, specially for clear, grid like things, etc...
});