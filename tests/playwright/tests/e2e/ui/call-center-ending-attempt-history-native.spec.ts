import { test } from './cc-native-test.mjs';
import fs from 'node:fs';
import { verifyEndingAttemptHistory } from './call-center-ending-attempt-history-native.mjs';

const session = JSON.parse(
  fs.readFileSync('/tmp/call-center-e2e-session.private', 'utf8')
);

test('ending attempt history reads real independent outcomes, paginates, persists and respects native destination and audit access', async ({
  page,
}, info) => {
  await verifyEndingAttemptHistory(
    page,
    info,
    session.pause_targets[info.project.name].ending_history
  );
});
