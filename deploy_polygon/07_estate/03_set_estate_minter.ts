import {DeployFunction} from 'hardhat-deploy/types';
import {skipUnlessTestnet} from '../../utils/network';

const func: DeployFunction = async function (hre) {
  const {deployments, getNamedAccounts} = hre;
  const {execute, read} = deployments;

  const {estateTokenAdmin} = await getNamedAccounts();

  const estateMinter = await deployments.get('EstateMinter');

  const currentMinter = await read('EstateToken', 'getMinter');
  const isMinter = currentMinter == estateMinter.address;

  if (!isMinter) {
    await execute(
      'EstateToken',
      {from: estateTokenAdmin, log: true},
      'changeMinter',
      estateMinter.address
    );
  }
};
export default func;
func.runAtTheEnd = true;
func.tags = ['PolygonEstateToken', 'PolygonEstateToken_setup'];
func.dependencies = ['PolygonEstateToken_deploy', 'PolygonEstateMinter_deploy'];
// TODO: Setup deploy-polygon folder and network.
func.skip = skipUnlessTestnet; // TODO enable