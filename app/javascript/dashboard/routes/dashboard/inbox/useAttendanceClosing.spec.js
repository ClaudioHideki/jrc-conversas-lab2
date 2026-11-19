import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { computed, defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useAttendanceClosing } from './useAttendanceClosing';
import { useQualificationDraft } from './useQualificationDraft';
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    qualifications: vi.fn(),
    agentState: vi.fn(),
    startQualification: vi.fn(),
    completeQualification: vi.fn(),
    saveQualificationDraft: vi.fn(),
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
let manual;
let draft;
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
  manual = { reason: ref(''), result: ref(''), note: ref('') };
  draft = useQualificationDraft(manual);
});

describe('native qualification manual draft boundaries', () => {
  it('hydrates saved values without inventing a label for a legacy reason', () => {
    draft.observe({
      ...pending,
      reason_code: 'legacy-custom',
      notes: 'SYNTHETIC saved note',
      draft_revision: 'revision-a',
    });
    expect(manual.reason.value).toBe('legacy-custom');
    expect(manual.note.value).toBe('SYNTHETIC saved note');
    expect(draft.saved.value).toBe(true);
    expect(draft.canSave.value).toBe(false);
  });

  it('preserves local answers while repeated clock observations retain the same manual revision', () => {
    draft.observe({ ...pending, draft_revision: 'revision-a' });
    manual.note.value = 'SYNTHETIC local note';
    draft.observe({
      ...pending,
      overdue: true,
      exceeded_seconds: 100,
      draft_revision: 'revision-a',
    });
    expect(manual.note.value).toBe('SYNTHETIC local note');
    expect(draft.conflict.value).toBe(false);
    expect(draft.canSave.value).toBe(true);
  });

  it('refreshes unedited answers from a newer native version', () => {
    draft.observe({
      ...pending,
      notes: 'SYNTHETIC old',
      draft_revision: 'revision-a',
    });
    draft.observe({
      ...pending,
      notes: 'SYNTHETIC current',
      draft_revision: 'revision-b',
    });
    expect(manual.note.value).toBe('SYNTHETIC current');
    expect(draft.revision.value).toBe('revision-b');
    expect(draft.conflict.value).toBe(false);
  });

  it('does not silently overwrite an edited answer when another client changes the same attendance', () => {
    draft.observe({ ...pending, draft_revision: 'revision-a' });
    manual.note.value = 'SYNTHETIC local edit';
    draft.observe({
      ...pending,
      notes: 'SYNTHETIC remote edit',
      draft_revision: 'revision-b',
    });
    expect(manual.note.value).toBe('SYNTHETIC local edit');
    expect(draft.revision.value).toBe('revision-a');
    expect(draft.conflict.value).toBe(true);
    expect(draft.canSave.value).toBe(false);
    expect(draft.remote.value.notes).toBe('SYNTHETIC remote edit');
  });

  it('requires a verified remote observation before a conflict can discard or reapply local answers', () => {
    draft.observe({ ...pending, draft_revision: 'revision-a' });
    manual.note.value = 'SYNTHETIC retained';
    draft.markConflict();
    expect(draft.useRemote()).toBe(false);
    expect(draft.reapply()).toBe(false);
    expect(manual.note.value).toBe('SYNTHETIC retained');
    draft.observe({
      ...pending,
      notes: 'SYNTHETIC server',
      draft_revision: 'revision-b',
    });
    expect(draft.reapply()).toBe(true);
    expect(manual.note.value).toBe('SYNTHETIC retained');
    expect(draft.revision.value).toBe('revision-b');
    expect(draft.canSave.value).toBe(true);
    expect(draft.saved.value).toBe(false);
  });

  it('uses remote answers only after the explicit conflict action', () => {
    draft.observe({ ...pending, draft_revision: 'revision-a' });
    manual.note.value = 'SYNTHETIC local';
    draft.markConflict();
    draft.observe({
      ...pending,
      notes: 'SYNTHETIC chosen remote',
      draft_revision: 'revision-b',
    });
    expect(draft.useRemote()).toBe(true);
    expect(manual.note.value).toBe('SYNTHETIC chosen remote');
    expect(draft.conflict.value).toBe(false);
    expect(draft.dirty.value).toBe(false);
  });

  it('does not reapply a completed attendance draft to another attendance ID', () => {
    draft.observe({ ...pending, draft_revision: 'revision-a' });
    manual.note.value = 'SYNTHETIC previous attendance';
    draft.observe({
      ...pending,
      id: 99,
      notes: 'SYNTHETIC another attendance',
      draft_revision: 'revision-b',
    });
    expect(draft.conflict.value).toBe(true);
    expect(draft.canReapply.value).toBe(false);
    expect(draft.reapply()).toBe(false);
    expect(manual.note.value).toBe('SYNTHETIC previous attendance');
  });

  it('preserves an unsaved answer after the native pending attendance ends elsewhere', () => {
    draft.observe({ ...pending, draft_revision: 'revision-a' });
    manual.note.value = 'SYNTHETIC do not discard';
    draft.observe(null);
    expect(draft.conflict.value).toBe(true);
    expect(draft.canReapply.value).toBe(false);
    expect(manual.note.value).toBe('SYNTHETIC do not discard');
    expect(draft.useRemote()).toBe(true);
    expect(manual.note.value).toBe('');
    expect(draft.revision.value).toBeNull();
  });

  it('does not retain already-saved editable fields after the attendance ends remotely without local changes', () => {
    draft.observe({
      ...pending,
      notes: 'SYNTHETIC already saved',
      draft_revision: 'revision-a',
    });
    draft.observe(null);
    expect(manual.note.value).toBe('');
    expect(draft.conflict.value).toBe(false);
    expect(draft.dirty.value).toBe(false);
  });

  it('does not let a late save acknowledgement overwrite edits made during that request', () => {
    draft.observe({ ...pending, draft_revision: 'revision-a' });
    manual.note.value = 'SYNTHETIC submitted';
    const submitted = draft.localValues();
    manual.note.value = 'SYNTHETIC typed later';
    draft.accept(
      {
        ...pending,
        notes: 'SYNTHETIC submitted',
        draft_revision: 'revision-b',
      },
      submitted
    );
    expect(manual.note.value).toBe('SYNTHETIC typed later');
    expect(draft.revision.value).toBe('revision-b');
    expect(draft.canSave.value).toBe(true);
    expect(draft.saved.value).toBe(false);
  });

  it.each([
    { ...pending, id: 99, draft_revision: 'revision-b' },
    { ...pending, draft_revision: null },
    {
      ...pending,
      draft_revision: 'revision-b',
      completed_at: '2026-10-16T12:00:02Z',
    },
  ])(
    'does not accept an invalid, unrelated or completed draft response',
    invalid => {
      draft.observe({ ...pending, draft_revision: 'revision-a' });
      manual.note.value = 'SYNTHETIC retained';
      expect(() => draft.accept(invalid, draft.localValues())).toThrow();
      expect(manual.note.value).toBe('SYNTHETIC retained');
      expect(draft.revision.value).toBe('revision-a');
    }
  );
});

describe('persisted attendance tabulation', () => {
  it('restores persisted manual answers and their native revision without sending a write', async () => {
    API.qualifications.mockResolvedValueOnce({
      data: {
        ...response.data,
        items: [
          {
            ...pending,
            reason_code: 'order',
            notes: 'SYNTHETIC saved answer',
            draft_revision: 'revision-a',
          },
        ],
      },
    });
    mount(Harness, { props });
    await flushPromises();
    expect(closing.reason.value).toBe('order');
    expect(closing.note.value).toBe('SYNTHETIC saved answer');
    expect(closing.draft.revision.value).toBe('revision-a');
    expect(closing.draft.saved.value).toBe(true);
    expect(API.saveQualificationDraft).not.toHaveBeenCalled();
    expect(API.completeQualification).not.toHaveBeenCalled();
  });

  it('does not overwrite the first typed answer while the post-start status refresh is still in flight', async () => {
    API.qualifications.mockResolvedValueOnce({
      data: {
        ...response.data,
        items: [],
        agent: { ...agent, pending_qualifications: [] },
      },
    });
    mount(Harness, { props });
    await flushPromises();
    API.startQualification.mockResolvedValueOnce({
      data: { item: { ...pending, draft_revision: 'revision-a' } },
    });
    let resolve;
    API.qualifications.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const starting = closing.start();
    await flushPromises();
    closing.note.value = 'SYNTHETIC first typed answer';
    resolve({
      data: {
        ...response.data,
        items: [{ ...pending, draft_revision: 'revision-a' }],
      },
    });
    await starting;
    expect(closing.note.value).toBe('SYNTHETIC first typed answer');
    expect(closing.draft.revision.value).toBe('revision-a');
    expect(closing.draft.canSave.value).toBe(true);
  });

  it('persists incomplete answers explicitly and applies the actual returned limit without completing or restarting attendance', async () => {
    API.qualifications.mockResolvedValueOnce({
      data: {
        ...response.data,
        items: [{ ...pending, draft_revision: 'revision-a' }],
      },
    });
    mount(Harness, { props });
    await flushPromises();
    closing.reason.value = 'order';
    closing.note.value = 'SYNTHETIC incomplete answer';
    API.saveQualificationDraft.mockResolvedValueOnce({
      data: {
        item: {
          ...pending,
          reason_code: 'order',
          notes: closing.note.value,
          acw_limit_seconds: 60,
          draft_revision: 'revision-b',
        },
        agent,
      },
    });
    expect(await closing.saveDraft()).toBe(true);
    expect(API.saveQualificationDraft).toHaveBeenCalledWith(
      1,
      11,
      {
        reason_code: 'order',
        outcome_code: '',
        notes: 'SYNTHETIC incomplete answer',
      },
      'revision-a'
    );
    expect(closing.limit.value).toBe(60);
    expect(closing.pending.value.started_at).toBe(pending.started_at);
    expect(closing.pending.value.completed_at).toBeNull();
    expect(closing.note.value).toBe('SYNTHETIC incomplete answer');
    expect(closing.draft.saved.value).toBe(true);
    expect(API.completeQualification).not.toHaveBeenCalled();
  });

  it('does not submit an unversioned draft while preserving legacy completion compatibility', async () => {
    mount(Harness, { props });
    await flushPromises();
    closing.reason.value = 'order';
    expect(await closing.saveDraft()).toBe(false);
    expect(API.saveQualificationDraft).not.toHaveBeenCalled();
    closing.result.value = 'completed';
    API.completeQualification.mockResolvedValueOnce({
      data: {
        item: { ...pending, completed_at: '2026-10-16T12:00:02Z' },
        agent,
      },
    });
    expect(await closing.complete()).toBe(true);
    expect(API.completeQualification).toHaveBeenCalledWith(1, 11, {
      reason_code: 'order',
      outcome_code: 'completed',
      notes: '',
    });
  });

  it('prevents duplicate draft submissions while retaining edits typed after the first submission started', async () => {
    API.qualifications.mockResolvedValueOnce({
      data: {
        ...response.data,
        items: [{ ...pending, draft_revision: 'revision-a' }],
      },
    });
    mount(Harness, { props });
    await flushPromises();
    closing.note.value = 'SYNTHETIC submitted answer';
    let resolve;
    API.saveQualificationDraft.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const saving = closing.saveDraft();
    closing.note.value = 'SYNTHETIC later local edit';
    expect(await closing.saveDraft()).toBe(false);
    resolve({
      data: {
        item: {
          ...pending,
          notes: 'SYNTHETIC submitted answer',
          draft_revision: 'revision-b',
        },
        agent,
      },
    });
    expect(await saving).toBe(true);
    expect(API.saveQualificationDraft).toHaveBeenCalledTimes(1);
    expect(closing.note.value).toBe('SYNTHETIC later local edit');
    expect(closing.draft.revision.value).toBe('revision-b');
    expect(closing.draft.canSave.value).toBe(true);
    expect(closing.draft.saved.value).toBe(false);
  });

  it('retains a failed draft for an explicit retry without pretending persistence succeeded', async () => {
    API.qualifications.mockResolvedValueOnce({
      data: {
        ...response.data,
        items: [{ ...pending, draft_revision: 'revision-a' }],
      },
    });
    mount(Harness, { props });
    await flushPromises();
    closing.note.value = 'SYNTHETIC retry answer';
    API.saveQualificationDraft.mockRejectedValueOnce(
      new Error('synthetic network failure')
    );
    expect(await closing.saveDraft()).toBe(false);
    expect(closing.note.value).toBe('SYNTHETIC retry answer');
    expect(closing.draft.revision.value).toBe('revision-a');
    expect(closing.draft.saved.value).toBe(false);
    expect(closing.saving.value).toBe(false);
    expect(closing.error.value).toBe(true);
  });

  it.each([401, 403, 404])(
    'clears private answers and review snapshots after a draft write is denied %s',
    async status => {
      API.qualifications.mockResolvedValueOnce({
        data: {
          ...response.data,
          items: [{ ...pending, draft_revision: 'revision-a' }],
        },
      });
      mount(Harness, { props });
      await flushPromises();
      closing.note.value = 'SYNTHETIC private answer';
      API.saveQualificationDraft.mockRejectedValueOnce({
        response: { status },
      });
      expect(await closing.saveDraft()).toBe(false);
      expect(closing.records.value).toEqual([]);
      expect(closing.note.value).toBe('');
      expect(closing.draft.revision.value).toBeNull();
      expect(closing.draft.remote.value).toBeNull();
    }
  );

  it('requires an explicit review after a stale draft response and never retries automatically', async () => {
    API.qualifications.mockResolvedValueOnce({
      data: {
        ...response.data,
        items: [{ ...pending, draft_revision: 'revision-a' }],
      },
    });
    mount(Harness, { props });
    await flushPromises();
    closing.reason.value = 'order';
    closing.result.value = 'pending';
    closing.note.value = 'SYNTHETIC my answer';
    API.saveQualificationDraft.mockRejectedValueOnce({
      response: {
        status: 409,
        data: { error: 'stale_configuration_revision' },
      },
    });
    API.qualifications.mockResolvedValueOnce({
      data: {
        ...response.data,
        items: [
          {
            ...pending,
            reason_code: 'information',
            notes: 'SYNTHETIC newer server answer',
            draft_revision: 'revision-b',
          },
        ],
      },
    });
    expect(await closing.saveDraft()).toBe(false);
    expect(closing.draft.conflict.value).toBe(true);
    expect(closing.note.value).toBe('SYNTHETIC my answer');
    expect(await closing.complete()).toBe(false);
    expect(API.completeQualification).not.toHaveBeenCalled();
    expect(API.saveQualificationDraft).toHaveBeenCalledTimes(1);
    expect(closing.draft.reapply()).toBe(true);
    expect(closing.draft.revision.value).toBe('revision-b');
    expect(closing.note.value).toBe('SYNTHETIC my answer');
    expect(API.saveQualificationDraft).toHaveBeenCalledTimes(1);
  });

  it('ignores a late draft acknowledgement after the current profile changes', async () => {
    API.qualifications.mockResolvedValueOnce({
      data: {
        ...response.data,
        items: [{ ...pending, draft_revision: 'revision-a' }],
      },
    });
    mount(Harness, { props });
    await flushPromises();
    closing.note.value = 'SYNTHETIC old profile answer';
    let resolve;
    API.saveQualificationDraft.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const saving = closing.saveDraft();
    API.qualifications.mockResolvedValueOnce({
      data: {
        ...response.data,
        items: [{ ...pending, draft_revision: 'revision-c' }],
      },
    });
    authority.value = 'actor9:roleB';
    await flushPromises();
    closing.note.value = 'SYNTHETIC current profile answer';
    resolve({
      data: {
        item: {
          ...pending,
          notes: 'SYNTHETIC old profile answer',
          draft_revision: 'revision-b',
        },
        agent,
      },
    });
    expect(await saving).toBe(false);
    expect(closing.note.value).toBe('SYNTHETIC current profile answer');
    expect(closing.draft.revision.value).toBe('revision-c');
    expect(closing.draft.saved.value).toBe(false);
  });

  it.each(['conflicting_acw_rules', 'attendance_cycle_conflict'])(
    'does not mistake %s for an editable manual revision conflict',
    async code => {
      API.qualifications.mockResolvedValueOnce({
        data: {
          ...response.data,
          items: [{ ...pending, draft_revision: 'revision-a' }],
        },
      });
      mount(Harness, { props });
      await flushPromises();
      closing.reason.value = 'order';
      closing.note.value = 'SYNTHETIC keep the real outcome';
      API.saveQualificationDraft.mockRejectedValueOnce({
        response: { status: 409, data: { error: code } },
      });
      expect(await closing.saveDraft()).toBe(false);
      expect(closing.writeFailure.value).toBe(code);
      expect(closing.note.value).toBe('SYNTHETIC keep the real outcome');
      expect(closing.draft.conflict.value).toBe(false);
      expect(API.qualifications).toHaveBeenCalledTimes(1);
      expect(API.saveQualificationDraft).toHaveBeenCalledTimes(1);
    }
  );

  it('does not restore an older in-flight clock read after a draft was saved', async () => {
    API.qualifications.mockResolvedValueOnce({
      data: {
        ...response.data,
        items: [{ ...pending, draft_revision: 'revision-a' }],
      },
    });
    mount(Harness, { props });
    await flushPromises();
    let resolve;
    API.qualifications.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const reading = closing.load();
    closing.reason.value = 'order';
    closing.note.value = 'SYNTHETIC saved current answer';
    API.saveQualificationDraft.mockResolvedValueOnce({
      data: {
        item: {
          ...pending,
          reason_code: 'order',
          notes: closing.note.value,
          acw_limit_seconds: 60,
          draft_revision: 'revision-b',
        },
        agent,
      },
    });
    expect(await closing.saveDraft()).toBe(true);
    resolve({
      data: {
        ...response.data,
        items: [{ ...pending, draft_revision: 'revision-a' }],
      },
    });
    await reading;
    expect(closing.draft.revision.value).toBe('revision-b');
    expect(closing.note.value).toBe('SYNTHETIC saved current answer');
    expect(closing.limit.value).toBe(60);
  });

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
