import { test } from './cc-native-test.mjs';
import fs from 'node:fs';
import { verifyEndingActivation } from './call-center-ending-activation-native.mjs';

const session = JSON.parse(
  fs.readFileSync('/tmp/call-center-e2e-session.private', 'utf8')
);

test('explicit ending activation persists its native review, rejects stale and denied operations and never replays earlier work', async ({
  page,
}, info) => {
  await verifyEndingActivation(
    page,
    info,
    session.pause_targets[info.project.name].ending_activation
  );
});
