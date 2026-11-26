import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useEndingAttemptHistory } from './useEndingAttemptHistory';
import {
  destinationHistoryRoute,
  validDestinationHistoryRow,
} from './endingDestinationHistoryContract';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { endingAttemptHistory: vi.fn() },
}));
enableAutoUnmount(afterEach);

const nativeRow = (overrides = {}) => ({
  id: 'typed:21',
  ledger: 'typed',
  attempt_id: '21',
  origin_id: '7',
  version_id: '8',
  rule_code: 'SYNTHETIC_TYPED_RULE',
  destination_kind: 'crm',
  operation: 'create_lead',
  can_reprocess_pending: false,
  can_resume_pending: false,
  can_retry_selected: false,
  readiness_id: null,
  rule_sha256: null,
  request_id: '12345678-1234-4234-8234-123456789abc',
  queued_at: '2026-11-25T12:00:00Z',
  outcome: 'pending',
  result_code: null,
  finished_at: null,
  execution_id: null,
  target: null,
  ...overrides,
});
const page = (items = [nativeRow()]) => ({
  data: {
    contract_version: 2,
    account_id: '1',
    qualification_id: '5',
    call_session_id: '9',
    items,
    meta: { page: 1, per_page: 20, total: items.length, pages: 1 },
  },
});
const setup = () => {
  const accountId = ref('1');
  const qualificationId = ref('5');
  const authorityKey = ref('SYNTHETIC_CURRENT_NATIVE_AUTHORITY');
  let history;
  mount(
    defineComponent({
      setup() {
        history = useEndingAttemptHistory({
          accountId,
          qualificationId,
          authorityKey,
          contractVersion: 2,
        });
        return () => h('div');
      },
    })
  );
  return { history, accountId, qualificationId, authorityKey };
};

describe('Explicit current multi-destination native history', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    API.endingAttemptHistory.mockResolvedValue(page());
  });

  it('opts into read contract 2 without starting an effect or accepting a legacy response', async () => {
    const { history } = setup();
    await history.open();
    expect(API.endingAttemptHistory).toHaveBeenCalledExactlyOnceWith('1', '5', {
      page: 1,
      history_contract: 2,
    });
    expect(history.items.value).toEqual([nativeRow()]);
    API.endingAttemptHistory.mockResolvedValueOnce({
      data: { ...page().data, contract_version: 1 },
    });
    await history.load();
    expect(history.items.value).toEqual([]);
    expect(history.error.value).toBe('LOAD_FAILED');
  });

  it('keeps overlapping native ledger sequence numbers distinct', async () => {
    const legacy = nativeRow({
      id: 'legacy:21',
      ledger: 'legacy',
      destination_kind: 'project_task',
      operation: 'create_task',
    });
    API.endingAttemptHistory.mockResolvedValueOnce(page([nativeRow(), legacy]));
    const { history } = setup();
    await history.open();
    expect(history.items.value.map(row => row.id)).toEqual([
      'typed:21',
      'legacy:21',
    ]);
    expect(history.error.value).toBe('');
  });

  it('rejects a typed row disguised as an executable legacy pending operation', async () => {
    API.endingAttemptHistory.mockResolvedValueOnce(
      page([nativeRow({ can_reprocess_pending: true })])
    );
    const { history } = setup();
    await history.open();
    expect(history.items.value).toEqual([]);
    expect(history.error.value).toBe('LOAD_FAILED');
    expect(API.endingAttemptHistory).toHaveBeenCalledTimes(1);
  });

  it('rejects a target kind that contradicts the immutable native operation', async () => {
    API.endingAttemptHistory.mockResolvedValueOnce(
      page([
        nativeRow({
          outcome: 'succeeded',
          result_code: 'completed',
          finished_at: '2026-11-25T12:01:00Z',
          execution_id: '12',
          target: { kind: 'project_task', id: '90', project_id: '40' },
        }),
      ])
    );
    const { history } = setup();
    await history.open();
    expect(history.items.value).toEqual([]);
    expect(history.error.value).toBe('LOAD_FAILED');
  });

  it('rejects retry hints without the exact authorized immutable review metadata', async () => {
    API.endingAttemptHistory.mockResolvedValueOnce(
      page([
        nativeRow({
          outcome: 'failed',
          result_code: 'destination_failure',
          finished_at: '2026-11-25T12:01:00Z',
          can_retry_selected: true,
        }),
      ])
    );
    const { history } = setup();
    await history.open();
    expect(history.items.value).toEqual([]);
    expect(history.error.value).toBe('LOAD_FAILED');
  });

  it('retains a successful receipt with no current target access', async () => {
    const succeeded = nativeRow({
      outcome: 'succeeded',
      result_code: 'completed',
      finished_at: '2026-11-25T12:01:00Z',
      execution_id: '12',
    });
    API.endingAttemptHistory.mockResolvedValueOnce(page([succeeded]));
    const { history } = setup();
    await history.open();
    expect(history.items.value).toEqual([succeeded]);
    expect(history.error.value).toBe('');
  });

  it('clears typed receipts synchronously when the effective profile changes', async () => {
    const { history, authorityKey } = setup();
    await history.open();
    authorityKey.value = 'SYNTHETIC_REVOKED';
    expect(history.items.value).toEqual([]);
    expect(history.opened.value).toBe(false);
  });

  it('does not populate another account from a delayed typed response', async () => {
    let resolve;
    API.endingAttemptHistory.mockReturnValueOnce(
      new Promise(accept => {
        resolve = accept;
      })
    );
    const { history, accountId } = setup();
    const pending = history.open();
    accountId.value = '2';
    resolve(page());
    await pending;
    expect(history.items.value).toEqual([]);
    expect(history.opened.value).toBe(false);
  });

  it('rejects unknown ledgers, operations and ambiguous numeric public IDs', () => {
    expect(validDestinationHistoryRow(nativeRow({ ledger: 'unknown' }))).toBe(
      false
    );
    expect(
      validDestinationHistoryRow(nativeRow({ operation: 'grant_access' }))
    ).toBe(false);
    expect(validDestinationHistoryRow(nativeRow({ id: '21' }))).toBe(false);
    expect(validDestinationHistoryRow(nativeRow({ id: 'typed:22' }))).toBe(
      false
    );
  });

  it('uses only existing fixed native routes instead of a URL returned in a receipt', () => {
    expect(destinationHistoryRoute({ kind: 'crm_lead', id: '9' }, '1')).toEqual(
      {
        name: 'crm_leads',
        params: { accountId: '1' },
        query: { leadId: '9' },
      }
    );
    expect(
      destinationHistoryRoute({ kind: 'crm_activity', id: '8' }, '1')?.query
    ).toEqual({ activityId: '8' });
    expect(
      destinationHistoryRoute({ kind: 'service_desk_ticket', id: '7' }, '1')
        ?.params
    ).toEqual({ accountId: '1', ticketId: '7' });
    expect(destinationHistoryRoute({ kind: 'external', id: '1' }, '1')).toBe(
      null
    );
    expect(
      destinationHistoryRoute({ kind: 'project_task', id: '9' }, '1')
    ).toBe(null);
  });
});
