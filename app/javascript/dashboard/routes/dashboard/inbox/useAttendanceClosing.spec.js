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
let enabled;
let authority;
let supports;
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
      enabled,
      authorityKey: authority,
      isVoice: computed(() => Boolean(props.currentCallId)),
      supportsClosing: supports,
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
  enabled = ref(true);
  supports = ref(true);
  authority = ref('actor9:roleA');
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

  it.each([401, 403, 404])(
    'clears private snapshots and draft after denied refresh %s',
    async status => {
      mount(Harness, { props });
      await flushPromises();
      closing.reason.value = 'order';
      closing.result.value = 'completed';
      closing.note.value = 'SYNTHETIC private draft';
      API.qualifications.mockRejectedValue({ response: { status } });
      await closing.load();
      expect(closing.records.value).toEqual([]);
      expect(closing.agent.value).toBeNull();
      expect(closing.policy.value).toBeNull();
      expect(closing.note.value).toBe('');
      expect(closing.pendingAttendance.value).toBeUndefined();
      expect(closing.error.value).toBe(true);
      expect(closing.loading.value).toBe(false);
    }
  );
  it('invalidates a same-account late read after an authority change', async () => {
    let resolve;
    API.qualifications.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    mount(Harness, { props });
    API.qualifications.mockResolvedValue({
      data: { ...response.data, items: [], agent: { account_user_id: 10 } },
    });
    authority.value = 'actor10:roleB';
    await flushPromises();
    resolve(response);
    await flushPromises();
    expect(closing.records.value).toEqual([]);
    expect(closing.agent.value.account_user_id).toBe(10);
    expect(showClosing).not.toHaveBeenCalled();
  });
  it('does not apply an old completion after the same actor changes profile', async () => {
    mount(Harness, { props });
    await flushPromises();
    closing.reason.value = 'order';
    closing.result.value = 'completed';
    let resolve;
    API.completeQualification.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const completing = closing.complete();
    API.qualifications.mockResolvedValue({
      data: { ...response.data, items: [], agent: { account_user_id: 9 } },
    });
    authority.value = 'actor9:restricted';
    await flushPromises();
    resolve({
      data: {
        item: { ...pending, completed_at: '2026-10-16T12:00:02Z' },
        agent,
      },
    });
    expect(await completing).toBe(false);
    expect(closing.records.value).toEqual([]);
    expect(closing.reason.value).toBe('');
    expect(closing.saving.value).toBe(false);
  });
  it('clears data on disabling and ignores a late response without another request', async () => {
    let resolve;
    API.qualifications.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    mount(Harness, { props });
    enabled.value = false;
    await flushPromises();
    resolve(response);
    await flushPromises();
    await closing.start();
    expect(await closing.complete()).toBe(false);
    expect(closing.records.value).toEqual([]);
    expect(closing.agent.value).toBeNull();
    expect(API.qualifications).toHaveBeenCalledTimes(1);
    expect(API.startQualification).not.toHaveBeenCalled();
    expect(API.completeQualification).not.toHaveBeenCalled();
  });
  it('prevents duplicate start requests while one is pending', async () => {
    mount(Harness, { props });
    await flushPromises();
    let resolve;
    API.startQualification.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const first = closing.start();
    await closing.start();
    expect(API.startQualification).toHaveBeenCalledTimes(1);
    resolve({ data: { item: pending } });
    await first;
    expect(closing.saving.value).toBe(false);
    expect(closing.pending.value.id).toBe(11);
  });
  it('ignores a late start after current authority is revoked', async () => {
    mount(Harness, { props });
    await flushPromises();
    let resolve;
    API.startQualification.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const starting = closing.start();
    enabled.value = false;
    await flushPromises();
    showClosing.mockClear();
    resolve({ data: { item: pending } });
    await starting;
    expect(closing.records.value).toEqual([]);
    expect(showClosing).not.toHaveBeenCalled();
    expect(closing.saving.value).toBe(false);
  });
  it.each([401, 403, 404])(
    'clears private draft after completion is denied %s',
    async status => {
      mount(Harness, { props });
      await flushPromises();
      closing.reason.value = 'order';
      closing.result.value = 'completed';
      closing.note.value = 'SYNTHETIC private';
      API.completeQualification.mockRejectedValue({ response: { status } });
      expect(await closing.complete()).toBe(false);
      expect(closing.records.value).toEqual([]);
      expect(closing.agent.value).toBeNull();
      expect(closing.note.value).toBe('');
      expect(closing.error.value).toBe(true);
    }
  );
  it('keeps a valid draft on an ordinary validation failure', async () => {
    mount(Harness, { props });
    await flushPromises();
    closing.reason.value = 'order';
    closing.result.value = 'completed';
    closing.note.value = 'SYNTHETIC retry';
    API.completeQualification.mockRejectedValue({ response: { status: 422 } });
    expect(await closing.complete()).toBe(false);
    expect(closing.pending.value.id).toBe(11);
    expect(closing.note.value).toBe('SYNTHETIC retry');
  });
  it('drops target history when closing support changes and uses the native agent endpoint', async () => {
    mount(Harness, { props });
    await flushPromises();
    supports.value = false;
    await flushPromises();
    await closing.start();
    expect(closing.records.value).toEqual([]);
    expect(closing.pending.value).toBeUndefined();
    expect(API.agentState).toHaveBeenCalledWith(1);
    expect(API.startQualification).not.toHaveBeenCalled();
  });

  it('hides stale observations on read failure but restores the same-context draft after reauthorization', async () => {
    mount(Harness, { props });
    await flushPromises();
    closing.reason.value = 'order';
    closing.note.value = 'SYNTHETIC retained offline draft';
    API.qualifications.mockRejectedValueOnce(
      new Error('temporary network failure')
    );
    await closing.load();
    expect(closing.records.value).toEqual([]);
    expect(closing.pending.value).toBeUndefined();
    expect(closing.note.value).toBe('SYNTHETIC retained offline draft');
    expect(closing.unverified.value).toBe(true);
    expect(closing.allowSelection('voice', 99)).toBe(false);
    expect(closing.allowSelection('whatsapp', 21)).toBe(true);
    await closing.start();
    expect(API.startQualification).not.toHaveBeenCalled();
    await closing.load();
    expect(closing.pending.value.id).toBe(11);
    expect(closing.reason.value).toBe('order');
    expect(closing.note.value).toBe('SYNTHETIC retained offline draft');
    expect(closing.error.value).toBe(false);
    expect(closing.unverified.value).toBe(false);
  });

  it('invalidates an in-flight completion after an authoritative denial without a profile refresh', async () => {
    mount(Harness, { props });
    await flushPromises();
    closing.reason.value = 'order';
    closing.result.value = 'completed';
    let resolve;
    API.completeQualification.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const completing = closing.complete();
    API.qualifications.mockRejectedValueOnce({ response: { status: 403 } });
    await closing.load();
    resolve({
      data: {
        item: { ...pending, completed_at: '2026-10-16T12:00:02Z' },
        agent,
      },
    });
    expect(await completing).toBe(false);
    expect(closing.records.value).toEqual([]);
    expect(closing.agent.value).toBeNull();
    expect(closing.saving.value).toBe(false);
    expect(closing.loading.value).toBe(false);
    expect(closing.unverified.value).toBe(true);
  });
  it('does not restore an in-flight start after a denied current read', async () => {
    mount(Harness, { props });
    await flushPromises();
    let resolve;
    API.startQualification.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const starting = closing.start();
    API.qualifications.mockRejectedValueOnce({ response: { status: 401 } });
    await closing.load();
    showClosing.mockClear();
    resolve({ data: { item: pending } });
    await starting;
    expect(closing.records.value).toEqual([]);
    expect(showClosing).not.toHaveBeenCalled();
    expect(closing.saving.value).toBe(false);
    expect(closing.loading.value).toBe(false);
  });
});
