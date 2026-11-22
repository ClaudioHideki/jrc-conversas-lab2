import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { computed, defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useAttendanceClosing } from './useAttendanceClosing';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    qualifications: vi.fn(),
    agentState: vi.fn(),
    qualificationFormContext: vi.fn(),
    confirmQualificationReason: vi.fn(),
    saveQualificationDraft: vi.fn(),
    completeQualification: vi.fn(),
  },
}));
enableAutoUnmount(afterEach);
const context = {
  revision: 1,
  integrity_sha256: 'a'.repeat(64),
  required: true,
  options: [{ code: 'synthetic_registered', name: 'SYNTHETIC registered' }],
};
const pending = {
  id: 11,
  account_id: 1,
  account_user_id: 9,
  call_session_id: 22,
  channel: 'voice',
  started_at: '2026-11-22T12:00:00Z',
  completed_at: null,
  acw_limit_seconds: 180,
  reason_code: 'synthetic_registered',
  notes: '',
  outcome_code: '',
  draft_revision: 'before',
  ending_reason_context: context,
};
const agent = {
  account_user_id: 9,
  state: 'acw',
  pending_qualifications: [pending],
};
const receipt = (changes = {}) => ({
  data: {
    item: {
      ...pending,
      notes: 'SYNTHETIC unsaved note',
      draft_revision: 'after',
      ending_reason_confirmation: {
        state: 'confirmed',
        reason_code: pending.reason_code,
        reason_label: 'SYNTHETIC registered',
        completes_acw: false,
        executes_integrations: false,
      },
      ...changes,
    },
    agent,
  },
});
let closing;
let authority;
let enabled;
const Harness = defineComponent({
  props: {
    accountId: { type: Number, default: 1 },
    currentCallId: { type: Number, default: 22 },
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
      },
      enabled,
      authorityKey: authority,
      supportsClosing: ref(true),
      isVoice: computed(() => true),
      now: ref(Date.parse('2026-11-22T12:00:03Z')),
      showClosing: vi.fn(),
      restoreSelection: vi.fn(),
    });
    return () => null;
  },
});
beforeEach(() => {
  vi.clearAllMocks();
  authority = ref('SYNTHETIC actor9/current-role');
  enabled = ref(true);
  API.qualifications.mockResolvedValue({
    data: { items: [pending], agent, policy: { limits: { voice: 180 } } },
  });
  API.qualificationFormContext.mockResolvedValue({
    data: { item: { ...pending, acw_form_context: { selected: null } } },
  });
  API.confirmQualificationReason.mockResolvedValue(receipt());
});

describe('Explicit native ending classification while ACW stays pending', () => {
  it('does not confirm on load, selection or ordinary note editing', async () => {
    mount(Harness);
    await flushPromises();
    closing.note.value = 'SYNTHETIC unsaved note';
    await flushPromises();
    expect(closing.canConfirmReason.value).toBe(true);
    expect(API.confirmQualificationReason).not.toHaveBeenCalled();
    expect(API.completeQualification).not.toHaveBeenCalled();
  });

  it('persists the complete local draft on explicit confirmation without completing ACW', async () => {
    mount(Harness);
    await flushPromises();
    closing.note.value = 'SYNTHETIC unsaved note';
    expect(await closing.confirmReason()).toBe(true);
    expect(API.confirmQualificationReason).toHaveBeenCalledWith(
      1,
      11,
      expect.objectContaining({
        qualification: {
          reason_code: pending.reason_code,
          outcome_code: '',
          notes: 'SYNTHETIC unsaved note',
        },
        expected_draft_revision: 'before',
        idempotency_key: expect.any(String),
      })
    );
    expect(closing.pending.value.completed_at).toBeNull();
    expect(closing.agent.value.state).toBe('acw');
    expect(closing.confirmation.value.state).toBe('confirmed');
    expect(API.completeQualification).not.toHaveBeenCalled();
  });

  it('keeps content after a failed request and reuses its idempotency key for the same explicit retry', async () => {
    API.confirmQualificationReason.mockRejectedValueOnce({
      response: { status: 503 },
    });
    mount(Harness);
    await flushPromises();
    closing.note.value = 'SYNTHETIC unsaved note';
    expect(await closing.confirmReason()).toBe(false);
    const first = API.confirmQualificationReason.mock.calls[0][2];
    expect(closing.note.value).toBe('SYNTHETIC unsaved note');
    expect(closing.confirmation.value).toBeNull();
    expect(await closing.confirmReason()).toBe(true);
    expect(API.confirmQualificationReason.mock.calls[1][2]).toEqual(first);
  });

  it('blocks double submission while a confirmation is unresolved', async () => {
    let resolve;
    API.confirmQualificationReason.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    mount(Harness);
    await flushPromises();
    closing.note.value = 'SYNTHETIC unsaved note';
    const first = closing.confirmReason();
    expect(await closing.confirmReason()).toBe(false);
    expect(API.confirmQualificationReason).toHaveBeenCalledTimes(1);
    resolve(receipt());
    expect(await first).toBe(true);
  });

  it.each([
    { id: 12 },
    { account_id: 2 },
    { account_user_id: 10 },
    {
      ending_reason_confirmation: {
        state: 'confirmed',
        reason_code: pending.reason_code,
        completes_acw: true,
        executes_integrations: true,
      },
    },
  ])(
    'rejects an incompatible confirmation receipt %j and retains the pending content',
    async changes => {
      API.confirmQualificationReason.mockResolvedValueOnce(receipt(changes));
      mount(Harness);
      await flushPromises();
      closing.note.value = 'SYNTHETIC unsaved note';
      expect(await closing.confirmReason()).toBe(false);
      expect(closing.note.value).toBe('SYNTHETIC unsaved note');
      expect(closing.confirmation.value).toBeNull();
      expect(API.completeQualification).not.toHaveBeenCalled();
    }
  );

  it('discards a late receipt after the account/attendance context changes', async () => {
    let resolve;
    API.confirmQualificationReason.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = mount(Harness);
    await flushPromises();
    closing.note.value = 'SYNTHETIC unsaved note';
    const request = closing.confirmReason();
    API.qualifications.mockResolvedValue({
      data: {
        items: [],
        agent: {
          account_user_id: 20,
          state: 'available',
          pending_qualifications: [],
        },
      },
    });
    await wrapper.setProps({ accountId: 2, currentCallId: 33 });
    await flushPromises();
    resolve(receipt());
    expect(await request).toBe(false);
    expect(closing.pending.value).toBeUndefined();
    expect(closing.confirmation.value).toBeNull();
    expect(closing.note.value).toBe('');
  });

  it('clears private content and ignores an in-flight confirmation after a profile change revokes current access', async () => {
    let resolve;
    API.confirmQualificationReason.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    mount(Harness);
    await flushPromises();
    closing.note.value = 'SYNTHETIC unsaved note';
    const request = closing.confirmReason();
    API.qualifications.mockRejectedValueOnce({ response: { status: 403 } });
    authority.value = 'SYNTHETIC actor9/revoked-role';
    await flushPromises();
    resolve(receipt());
    expect(await request).toBe(false);
    expect(closing.pending.value).toBeUndefined();
    expect(closing.note.value).toBe('');
    expect(closing.confirmation.value).toBeNull();
    expect(await closing.confirmReason()).toBe(false);
    expect(API.confirmQualificationReason).toHaveBeenCalledTimes(1);
  });
});
