import { test } from './cc-native-test.mjs';
import fs from 'node:fs';
import { verifyNativeRecordingHistory } from './call-center-recordings-native.mjs';

const session = JSON.parse(
  fs.readFileSync('/tmp/call-center-e2e-session.private', 'utf8')
);

test('native own-extension recordings require current scoped authority and play actual isolated bytes', async ({
  page,
}, info) => {
  test.setTimeout(150000);
  await verifyNativeRecordingHistory(
    page,
    info,
    session.pause_targets[info.project.name].recordings
  );
});
