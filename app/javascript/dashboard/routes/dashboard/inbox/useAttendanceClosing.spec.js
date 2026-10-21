import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { computed, defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useAttendanceClosing } from './useAttendanceClosing';
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    qualifications: vi.fn(),
    agentState: vi.fn(),
    startQualification: vi.fn(),
    completeQualification: vi.fn(),
  },
}));
enableAutoUnmount(afterEach);
const pending = {
  id: 11,
  account_id: 1,
  account_user_id: 9,
  conversation_display_id: 21,
  conversation_id: 101,
  channel: 'whatsapp',
  started_at: '2026-10-16T12:00:00Z',
  acw_limit_seconds: 7,
  completed_at: null,
  overdue: false,
};
const agent = {
  account_user_id: 9,
  state: 'acw',
  pending_qualifications: [pending],
};
const response = {
  data: {
    items: [pending],
    agent,
    policy: { limits: { voice: 5, whatsapp: 7 } },
  },
};
let closing;
let now;
let showClosing;
let restore;
const Harness = defineComponent({
  props: {
    accountId: { type: Number, required: true },
    currentCallId: { type: Number, default: null },
    currentConversationId: { type: Number, default: null },
    ready: { type: Boolean, default: true },
  },
  setup(props) {
    closing = useAttendanceClosing({
      props: {
        get accountId() {
          return props.accountId;
        },
        get currentCallId() {
          return props.currentCallId;
        },
        get currentConversationId() {
          return props.currentConversationId;
        },
        get ready() {
          return props.ready;
        },
      },
      now,
      isVoice: computed(() => Boolean(props.currentCallId)),
      supportsClosing: computed(() => true),
      showClosing,
      restoreSelection: restore,
    });
    return () => null;
  },
});
const props = {
  accountId: 1,
  currentCallId: null,
  currentConversationId: 21,
  ready: true,
};
beforeEach(() => {
  vi.clearAllMocks();
  now = ref(Date.parse('2026-10-16T12:00:02Z'));
  showClosing = vi.fn();
  restore = vi.fn();
  API.qualifications.mockResolvedValue(response);
  API.agentState.mockResolvedValue({ data: { item: agent } });
});

describe('persisted attendance tabulation', () => {
  it('uses the backend policy and restores a pending attendance after refresh', async () => {
    mount(Harness, { props });
    await flushPromises();
    expect(closing.pending.value.id).toBe(11);
    expect(closing.limit.value).toBe(7);
    expect(closing.elapsed.value).toBe(2);
    expect(showClosing).toHaveBeenCalled();
  });
  it('keeps the obligation and marks overdue when the configured deadline is reached', async () => {
    mount(Harness, { props });
    await flushPromises();
    now.value += 5000;
    expect(closing.overdue.value).toBe(true);
    expect(closing.pending.value.id).toBe(11);
    expect(closing.allowSelection('whatsapp', 22)).toBe(false);
  });
  it('blocks another Voice or digital attendance while pending', async () => {
    mount(Harness, { props });
    await flushPromises();
    expect(closing.allowSelection('voice', 2)).toBe(false);
    expect(closing.allowSelection('whatsapp', 22)).toBe(false);
    expect(closing.allowSelection('whatsapp', 21)).toBe(true);
    expect(closing.blocked.value).toBe(true);
  });
  it('does not submit missing mandatory fields', async () => {
    mount(Harness, { props });
    await flushPromises();
    closing.reason.value = 'order';
    await closing.complete();
    expect(API.completeQualification).not.toHaveBeenCalled();
    expect(closing.pending.value.id).toBe(11);
  });
  it('keeps the form on server failure', async () => {
    mount(Harness, { props });
    await flushPromises();
    closing.reason.value = 'order';
    closing.result.value = 'completed';
    closing.note.value = 'Keep this';
    API.completeQualification.mockRejectedValue(
      new Error('persistence failed')
    );
    expect(await closing.complete()).toBe(false);
    expect(closing.reason.value).toBe('order');
    expect(closing.note.value).toBe('Keep this');
    expect(closing.pending.value.id).toBe(11);
    expect(closing.error.value).toBe(true);
  });
  it('clears the form only after persisted completion and keeps operational history', async () => {
    mount(Harness, { props });
    await flushPromises();
    closing.reason.value = 'order';
    closing.result.value = 'completed';
    closing.note.value = 'Keep in history';
    const saved = {
      ...pending,
      completed_at: '2026-10-16T12:00:02Z',
      reason_code: 'order',
      outcome_code: 'completed',
      notes: 'Keep in history',
    };
    API.completeQualification.mockResolvedValue({
      data: {
        item: saved,
        agent: {
          account_user_id: 9,
          state: 'available',
          pending_qualifications: [],
        },
      },
    });
    expect(await closing.complete()).toBe(true);
    expect(closing.pending.value).toBeUndefined();
    expect(closing.reason.value).toBe('');
    expect(closing.records.value[0].notes).toBe('Keep in history');
    expect(closing.allowSelection('whatsapp', 22)).toBe(true);
  });
  it('ignores late Account A completion while Account B has its own pending draft', async () => {
    const wrapper = mount(Harness, { props });
    await flushPromises();
    closing.reason.value = 'order';
    closing.result.value = 'completed';
    let resolve;
    API.completeQualification.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const completing = closing.complete();
    const recordB = {
      ...pending,
      id: 12,
      account_id: 2,
      account_user_id: 10,
      conversation_display_id: 31,
    };
    API.qualifications.mockResolvedValue({
      data: {
        ...response.data,
        items: [recordB],
        agent: { account_user_id: 10, pending_qualifications: [recordB] },
      },
    });
    await wrapper.setProps({ accountId: 2, currentConversationId: 31 });
    await flushPromises();
    closing.reason.value = 'information';
    closing.result.value = 'pending';
    closing.note.value = 'Account B draft';
    resolve({
      data: {
        item: { ...pending, completed_at: '2026-10-16T12:00:02Z' },
        agent: { state: 'available' },
      },
    });
    expect(await completing).toBe(false);
    expect(closing.records.value[0].account_id).toBe(2);
    expect(closing.reason.value).toBe('information');
    expect(closing.note.value).toBe('Account B draft');
    expect(closing.saving.value).toBe(false);
  });
  it('ignores a late Account A status/history response', async () => {
    let resolve;
    API.qualifications.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = mount(Harness, { props });
    API.qualifications.mockResolvedValue({
      data: {
        ...response.data,
        items: [],
        agent: { account_user_id: 10, pending_qualifications: [] },
      },
    });
    await wrapper.setProps({ accountId: 2, currentConversationId: 31 });
    await flushPromises();
    resolve(response);
    await flushPromises();
    expect(closing.records.value).toEqual([]);
    expect(closing.agent.value.account_user_id).toBe(10);
  });
});
