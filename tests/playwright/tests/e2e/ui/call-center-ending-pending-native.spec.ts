import { test } from './cc-native-test.mjs';
import fs from 'node:fs';
import { verifySelectedPendingEnding } from './call-center-ending-pending-native.mjs';

const session = JSON.parse(
  fs.readFileSync('/tmp/call-center-e2e-session.private', 'utf8')
);

test('selected pending automation requires real owner review and commits only its native Project effect', async ({
  page,
}, info) => {
  await verifySelectedPendingEnding(
    page,
    info,
    session.pause_targets[info.project.name].ending_pending
  );
});
