import { verifyNativeRecordingRelationship } from './call-center-recording-relationship-native.mjs';
import { verifyNativeRecordingQualityReport } from './call-center-recording-quality-report-native.mjs';
import { test } from './cc-native-test.mjs';
import fs from 'node:fs';
import { verifyNativeQualityReview } from './call-center-quality-review-native.mjs';
import { verifyNativeRecordingHistory } from './call-center-recordings-native.mjs';
import { verifyNativeRecordingCustomerLink } from './call-center-recording-customer-link-native.mjs';

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

test('native human Nico correction preserves immutable source, reviewed conflicts and independent authority', async ({
  page,
}, info) => {
  test.setTimeout(180000);
  await verifyNativeQualityReview(
    page,
    info,
    session.pause_targets[info.project.name].recordings
  );
});

test('native explicit customer linkage preserves source history, current authority and initial-link conflicts', async ({
  page,
}, info) => {
  test.setTimeout(180000);
  await verifyNativeRecordingCustomerLink(
    page,
    info,
    session.pause_targets[info.project.name].recordings
  );
});

test('native whole-period sentiment filters reuse real recording scopes, pagination, details and current profiles', async ({
  page,
}, info) => {
  test.setTimeout(180000);
  const other = Object.entries(session.pause_targets).find(
    ([name]) => name !== info.project.name
  );
  if (!other) throw new Error('Independent synthetic account required');
  await verifyNativeRecordingQualityReport(
    page,
    info,
    session.pause_targets[info.project.name].recordings,
    other[1].recordings.operator
  );
});

test('native reviewed recording creates one authorized Relationship activity through the reused form and workflow', async ({ page }, info) => {
  test.setTimeout(180000);
  await verifyNativeRecordingRelationship(page, info, session.pause_targets[info.project.name].recordings);
});
