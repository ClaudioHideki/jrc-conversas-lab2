import { afterEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import RecordingEndingActions from './RecordingEndingActions.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    recordingEndingContext: vi.fn(),
    endingAttemptHistory: vi.fn(),
    manualEndingActions: vi.fn(),
    runPendingEndingAttempt: vi.fn(),
    requestEndingDestination: vi.fn(),
  },
}));
enableAutoUnmount(afterEach);
afterEach(() => vi.resetAllMocks());
const body = () => ({
  contract_version: 1,
  account_id: '1',
  recording_id: '5',
  call_session_id: '7',
  call_id: 'SYNTHETIC-call',
  items: [
    { id: '11', account_user_id: '4', started_at: null, completed_at: null },
  ],
  meta: { page: 1, per_page: 20, total: 1, pages: 1 },
});
const render = (stubHistory = true) =>
  mount(RecordingEndingActions, {
    props: {
      accountId: '1',
      recordingId: '5',
      callSessionId: '7',
      callId: 'SYNTHETIC-call',
      authorityKey: 'SYNTHETIC-current-actor',
    },
    global: { stubs: { EndingAttemptHistory: stubHistory } },
  });
const load = async wrapper => {
  await wrapper.get('[data-recording-actions-load]').trigger('click');
  await flushPromises();
};

describe('existing native ending actions reached from the authorized recording', () => {
  it('uses the actual native receipt widget without manual, retry or pending-write controls in the closable recording popup', async () => {
    API.recordingEndingContext.mockResolvedValueOnce({ data: body() });
    API.endingAttemptHistory.mockResolvedValueOnce({
      data: {
        contract_version: 2,
        account_id: '1',
        qualification_id: '11',
        call_session_id: '7',
        items: [
          {
            id: 'legacy:5',
            ledger: 'legacy',
            attempt_id: '5',
            origin_id: '6',
            version_id: '7',
            operation: 'create_task',
            destination_kind: 'project_task',
            rule_code: 'SYNTHETIC_PENDING',
            request_id: '11111111-1111-4111-8111-111111111111',
            queued_at: '2026-11-26T18:00:00Z',
            can_reprocess_pending: true,
            outcome: 'pending',
            result_code: null,
            finished_at: null,
            execution_id: null,
            target: null,
          },
        ],
        meta: { page: 1, per_page: 20, total: 1, pages: 1 },
      },
    });
    const wrapper = render(false);
    await load(wrapper);
    await wrapper.get('[data-recording-actions-select="11"]').trigger('click');
    await wrapper.get('[data-open-ending-attempt-history]').trigger('click');
    await flushPromises();
    expect(wrapper.findAll('[data-ending-attempt-row]')).toHaveLength(1);
    expect(wrapper.text()).toContain('SYNTHETIC_PENDING');
    expect(wrapper.find('[data-review-selected-ending-pending]').exists()).toBe(
      false
    );
    expect(
      wrapper.find('[data-resume-selected-ending-destination]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-retry-selected-ending-destination]').exists()
    ).toBe(false);
    expect(wrapper.find('[data-manual-ending-actions]').exists()).toBe(false);
    expect(API.manualEndingActions).not.toHaveBeenCalled();
    expect(API.runPendingEndingAttempt).not.toHaveBeenCalled();
    expect(API.requestEndingDestination).not.toHaveBeenCalled();
    expect(API.endingAttemptHistory).toHaveBeenCalledWith('1', '11', {
      page: 1,
      history_contract: 2,
    });
  });
  it('distinguishes an actually started ACW from completion without changing it through a history read', async () => {
    const pending = body();
    pending.items[0].started_at = '2026-11-26T18:00:00Z';
    API.recordingEndingContext.mockResolvedValueOnce({ data: pending });
    const wrapper = render();
    await load(wrapper);
    expect(wrapper.text()).toContain('ACW_PENDING');
    expect(wrapper.text()).not.toContain('ACW_COMPLETED');
    const completed = body();
    completed.items[0].started_at = '2026-11-26T18:00:00Z';
    completed.items[0].completed_at = '2026-11-26T18:01:00Z';
    API.recordingEndingContext.mockResolvedValueOnce({ data: completed });
    await load(wrapper);
    expect(wrapper.text()).toContain('ACW_COMPLETED');
    expect(wrapper.text()).not.toContain('ACW_PENDING');
  });
  it('does not create or query attendance on mount and opens the existing controls only after explicit selection', async () => {
    API.recordingEndingContext.mockResolvedValue({ data: body() });
    const wrapper = render();
    expect(API.recordingEndingContext).not.toHaveBeenCalled();
    await load(wrapper);
    expect(API.recordingEndingContext).toHaveBeenCalledWith('1', '5', 1);
    expect(
      wrapper.findComponent({ name: 'EndingAttemptHistory' }).exists()
    ).toBe(false);
    await wrapper.get('[data-recording-actions-select="11"]').trigger('click');
    expect(
      wrapper.getComponent({ name: 'EndingAttemptHistory' }).props()
    ).toMatchObject({
      accountId: '1',
      qualificationId: '11',
      authorityKey: expect.stringContaining('SYNTHETIC-current-actor'),
      readOnly: true,
    });
    expect(wrapper.text()).toContain('ACW_NOT_STARTED');
  });

  it('keeps absent qualifications distinct from a failure and never invents a task or completed ACW', async () => {
    const data = body();
    data.items = [];
    data.meta = { page: 1, per_page: 20, total: 0, pages: 0 };
    API.recordingEndingContext.mockResolvedValue({ data });
    const wrapper = render();
    await load(wrapper);
    expect(wrapper.get('[data-recording-actions-empty]').text()).toContain(
      'EMPTY'
    );
    expect(
      wrapper.findComponent({ name: 'EndingAttemptHistory' }).exists()
    ).toBe(false);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(
      wrapper.get('[data-recording-actions-next]').attributes('disabled')
    ).toBeDefined();
  });

  it.each(['account_id', 'recording_id', 'call_session_id', 'call_id'])(
    'rejects a mismatched %s without opening another attendance',
    async key => {
      const data = body();
      data[key] = '99';
      API.recordingEndingContext.mockResolvedValue({ data });
      const wrapper = render();
      await load(wrapper);
      expect(wrapper.get('[role="alert"]').text()).toContain('ERROR');
      expect(wrapper.find('[data-recording-actions-select]').exists()).toBe(
        false
      );
    }
  );

  it('clears links and selected controls on actor, recording and account changes and ignores the old reply', async () => {
    let resolveFirst;
    API.recordingEndingContext.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveFirst = resolve;
        })
    );
    const wrapper = render();
    await wrapper.get('[data-recording-actions-load]').trigger('click');
    await wrapper.setProps({
      accountId: '2',
      recordingId: '8',
      authorityKey: 'SYNTHETIC-other-actor',
    });
    resolveFirst({ data: body() });
    await flushPromises();
    expect(wrapper.find('[data-recording-actions-select]').exists()).toBe(
      false
    );
    expect(
      wrapper.findComponent({ name: 'EndingAttemptHistory' }).exists()
    ).toBe(false);
    expect(API.recordingEndingContext).toHaveBeenCalledTimes(1);
  });

  it('blocks double load while in flight and preserves denial for an explicit fresh retry', async () => {
    let reject;
    API.recordingEndingContext.mockImplementationOnce(
      () =>
        new Promise((_resolve, failure) => {
          reject = failure;
        })
    );
    const wrapper = render();
    await wrapper.get('[data-recording-actions-load]').trigger('click');
    expect(
      wrapper.get('[data-recording-actions-load]').attributes('disabled')
    ).toBeDefined();
    await wrapper.get('[data-recording-actions-load]').trigger('click');
    expect(API.recordingEndingContext).toHaveBeenCalledTimes(1);
    reject({ response: { status: 403 } });
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('DENIED');
    API.recordingEndingContext.mockResolvedValueOnce({ data: body() });
    await load(wrapper);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(API.recordingEndingContext).toHaveBeenCalledTimes(2);
  });

  it('uses the bounded native next page and discards the selected controls when refreshing', async () => {
    const first = body();
    first.meta.total = 21;
    first.meta.pages = 2;
    first.items = Array.from({ length: 20 }, (_, index) => ({
      ...body().items[0],
      id: String(11 + index),
      account_user_id: String(4 + index),
    }));
    API.recordingEndingContext.mockResolvedValueOnce({ data: first });
    const wrapper = render();
    await load(wrapper);
    await wrapper.get('[data-recording-actions-select="11"]').trigger('click');
    const second = body();
    second.items[0].id = '31';
    second.meta = { page: 2, per_page: 20, total: 21, pages: 2 };
    API.recordingEndingContext.mockResolvedValueOnce({ data: second });
    await wrapper.get('[data-recording-actions-next]').trigger('click');
    await flushPromises();
    expect(API.recordingEndingContext).toHaveBeenLastCalledWith('1', '5', 2);
    expect(wrapper.find('[data-recording-actions-select="11"]').exists()).toBe(
      false
    );
    expect(
      wrapper.findComponent({ name: 'EndingAttemptHistory' }).exists()
    ).toBe(false);
    expect(
      wrapper.get('[data-recording-actions-next]').attributes('disabled')
    ).toBeDefined();
  });
});
