import { describe, expect, it } from 'vitest';
import { verifiedPauseApprovalPreview } from './pauseApprovalPreview';
import { pausePreviewData, pauseValues } from './pauseApprovalPreview.fixtures';

describe('all-scope pause review presentation coherence', () => {
  const context = { account: '1', member: '2' };
  it('preserves both affected companies even when a single operating queue is selected', () => {
    const values = pauseValues();
    const data = pausePreviewData(values);
    const before = structuredClone(data);
    const result = verifiedPauseApprovalPreview(data, context, values);
    expect(result.scopes).toHaveLength(2);
    expect(
      result.scopes.flatMap(row => row.units.map(unit => unit.name))
    ).toEqual(['SYNTHETIC unidade A', 'SYNTHETIC unidade B']);
    expect(result.digest).toBe(data.preview.digest);
    expect(data).toEqual(before);
    expect(values.queue_id).toBe('50');
  });

  it.each([
    [
      'wrong account',
      data => {
        data.account_id = '9';
      },
    ],
    [
      'wrong member',
      data => {
        data.account_user_id = '9';
      },
    ],
    [
      'foreign inner account',
      data => {
        data.preview.payload.coverage.account_id = '9';
      },
    ],
    [
      'malformed actor',
      data => {
        data.preview.payload.coverage.actor_user_id = null;
      },
    ],
    [
      'narrowed impact',
      data => {
        data.preview.payload.coverage.all_affected_units = false;
      },
    ],
    [
      'provider claim',
      data => {
        data.preview.provider_confirmed = true;
      },
    ],
    [
      'remote claim',
      data => {
        data.preview.local_only = false;
      },
    ],
    [
      'changed request',
      data => {
        data.preview.payload.request_id = 'other';
      },
    ],
    [
      'changed queue',
      data => {
        data.preview.payload.intent.queue_id = '99';
      },
    ],
    [
      'changed reason',
      data => {
        data.preview.payload.intent.reason_code = 'other';
      },
    ],
    [
      'changed private text',
      data => {
        data.preview.payload.intent.justification = 'other';
      },
    ],
    [
      'missing scope',
      data => {
        data.preview.payload.coverage.groups.pop();
      },
    ],
    [
      'duplicated unit',
      data => {
        data.preview.payload.coverage.units.push(
          data.preview.payload.coverage.units[0]
        );
      },
    ],
    [
      'duplicated scope',
      data => {
        data.preview.payload.coverage.groups.push(
          data.preview.payload.coverage.groups[0]
        );
      },
    ],
    [
      'missing unit name',
      data => {
        data.preview.payload.coverage.units[0].name = '';
      },
    ],
    [
      'foreign corporate mapping',
      data => {
        data.preview.payload.coverage.units[0].scope.issuer_company_id = '99';
      },
    ],
    [
      'malformed digest',
      data => {
        data.preview.digest = 'invalid';
      },
    ],
    [
      'unexpected legacy fallback',
      data => {
        data.preview.required = false;
      },
    ],
    [
      'unknown scoped unit',
      data => {
        data.preview.payload.coverage.groups[0].unit_ids = ['99'];
      },
    ],
  ])(
    'rejects %s without treating it as a reviewed complete impact',
    (_, change) => {
      const values = pauseValues();
      const data = pausePreviewData(values);
      change(data);
      expect(verifiedPauseApprovalPreview(data, context, values)).toBeNull();
    }
  );
});
