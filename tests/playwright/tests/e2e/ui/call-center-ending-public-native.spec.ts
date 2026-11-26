import { test } from './cc-native-test.mjs';
import fs from 'node:fs';
import { verifyPublicEndingExecution } from './call-center-ending-public-native.mjs';

const session = JSON.parse(
  fs.readFileSync('/tmp/call-center-e2e-session.private', 'utf8')
);

test('explicit native ending consent, actual worker rollback, selected retry and independent ACW survive reload', async ({
  page,
}, info) => {
  test.setTimeout(180000);
  await verifyPublicEndingExecution(
    page,
    info,
    session.pause_targets[info.project.name].ending_operational
  );
});
