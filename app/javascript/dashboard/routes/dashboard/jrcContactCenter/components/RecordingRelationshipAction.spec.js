import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { computed, defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import RecordingRelationshipAction from './RecordingRelationshipAction.vue';

const mocks = vi.hoisted(() => ({ actor: null }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.actor,
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => (values ? `${key} ${JSON.stringify(values)}` : key),
  }),
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    recordingRelationshipActivities: vi.fn(),
    createRecordingRelationshipActivity: vi.fn(),
  },
}));
const OpsModal = defineComponent({
  props: {
    title: { type: String, required: true },
    busy: { type: Boolean, default: false },
  },
  emits: ['close'],
  setup(props, { emit }) {
    return {
      heading: computed(() => props.title),
      blocked: computed(() => props.busy),
      close: () => emit('close'),
    };
  },
  template:
    '<section role="dialog" :aria-label="heading"><slot /><button data-close-intake :disabled="blocked" @click="close"></button></section>',
});
const preview = (extra = {}) => ({
  contract_version: 1,
  account_id: '1',
  user_id: '7',
  recording_id: '8',
  call_session_id: '9',
  call_id: 'SYNTHETIC current call',
  contact_id: '10',
  time_zone: 'America/Sao_Paulo',
  origin_revision: 'a'.repeat(64),
  items: [{ id: '33', label: 'SYNTHETIC permitted portfolio', can_work: true }],
  meta: { page: 1, per_page: 20, total: 1, pages: 1 },
  ...extra,
});
const receipt = (extra = {}) => ({
  contract_version: 1,
  account_id: '1',
  recording_id: '8',
  call_session_id: '9',
  assignment_id: '33',
  activity_id: '44',
  replayed: false,
  target: { kind: 'crm_activity', id: '44' },
  ...extra,
});
const setup = (props = {}) =>
  mount(RecordingRelationshipAction, {
    props: {
      accountId: '1',
      recordingId: '8',
      callSessionId: '9',
      callId: 'SYNTHETIC current call',
      contactId: '10',
      enabled: true,
      ...props,
    },
    global: { stubs: { OpsModal, RouterLink: true } },
  });
const open = async wrapper => {
  await wrapper.get('[data-open-recording-relationship]').trigger('click');
  await flushPromises();
};
const fill = async wrapper => {
  await wrapper.get('[data-recording-relationship-portfolio]').setValue('33');
  await wrapper
    .get('[data-native-relationship-activity-title]')
    .setValue('SYNTHETIC reviewed call activity');
  await wrapper
    .get('[data-native-relationship-activity-deadline]')
    .setValue('2026-11-30T10:00');
};
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.actor = ref({
    id: 7,
    accounts: [
      { id: 1, role: 'agent', permissions: ['jrc_relationship_manage'] },
    ],
  });
  API.recordingRelationshipActivities.mockResolvedValue({ data: preview() });
  API.createRecordingRelationshipActivity.mockResolvedValue({
    data: receipt(),
  });
});

describe('native recording to existing Relationship activity intake', () => {
  it('pages native portfolios without auto-selection, creation or carrying the previous selection', async () => {
    API.recordingRelationshipActivities
      .mockResolvedValueOnce({
        data: preview({ meta: { page: 1, per_page: 20, total: 21, pages: 2 } }),
      })
      .mockResolvedValueOnce({
        data: preview({
          items: [
            { id: '34', label: 'SYNTHETIC second native page', can_work: true },
          ],
          meta: { page: 2, per_page: 20, total: 21, pages: 2 },
        }),
      });
    const wrapper = setup();
    await open(wrapper);
    await fill(wrapper);
    await wrapper.get('nav').findAll('button')[1].trigger('click');
    await flushPromises();
    expect(API.recordingRelationshipActivities).toHaveBeenLastCalledWith(
      '1',
      '8',
      2,
      { signal: expect.any(AbortSignal) }
    );
    expect(
      wrapper.get('[data-recording-relationship-portfolio]').element.value
    ).toBe('');
    expect(wrapper.text()).toContain('SYNTHETIC second native page');
    expect(wrapper.text()).not.toContain('SYNTHETIC permitted portfolio');
    expect(API.createRecordingRelationshipActivity).not.toHaveBeenCalled();
  });

  it('clears denied context and loads fresh choices only after explicit user recovery', async () => {
    API.recordingRelationshipActivities.mockRejectedValueOnce({
      response: { status: 403 },
    });
    const wrapper = setup();
    await open(wrapper);
    expect(wrapper.get('[role="alert"]').text()).toContain('DENIED');
    expect(wrapper.find('form').exists()).toBe(false);
    const retry = wrapper
      .findAll('button')
      .find(button => button.text().includes('CONTEXT.RETRY'));
    await retry.trigger('click');
    await flushPromises();
    await fill(wrapper);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(API.createRecordingRelationshipActivity).toHaveBeenCalledTimes(1);
    expect(
      API.createRecordingRelationshipActivity.mock.calls[0][2].request_id
    ).toMatch(/^[0-9a-f-]{36}$/);
    expect(wrapper.find('[data-recording-relationship-receipt]').exists()).toBe(
      true
    );
  });

  it('clears drafts and portfolio labels when current write permission is denied by the server', async () => {
    API.createRecordingRelationshipActivity.mockRejectedValueOnce({
      response: { status: 401 },
    });
    const wrapper = setup();
    await open(wrapper);
    await fill(wrapper);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('DENIED');
    expect(wrapper.find('form').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC permitted portfolio');
    expect(wrapper.find('[data-retry-recording-relationship]').exists()).toBe(
      false
    );
    expect(API.createRecordingRelationshipActivity).toHaveBeenCalledTimes(1);
  });

  it('does not load, open or write while native operating context is unavailable', () => {
    const wrapper = setup({ enabled: false });
    expect(wrapper.find('[data-open-recording-relationship]').exists()).toBe(
      false
    );
    expect(API.recordingRelationshipActivities).not.toHaveBeenCalled();
    expect(API.createRecordingRelationshipActivity).not.toHaveBeenCalled();
  });

  it('reads native choices on explicit open and requires a deliberate portfolio selection', async () => {
    const wrapper = setup();
    expect(API.recordingRelationshipActivities).not.toHaveBeenCalled();
    await open(wrapper);
    expect(API.recordingRelationshipActivities).toHaveBeenCalledWith(
      '1',
      '8',
      1,
      { signal: expect.any(AbortSignal) }
    );
    expect(
      wrapper.get('[data-recording-relationship-portfolio]').element.value
    ).toBe('');
    expect(
      wrapper.find('[data-native-relationship-activity-form]').exists()
    ).toBe(false);
    expect(
      wrapper.get('[data-recording-relationship-origin]').text()
    ).toContain('SYNTHETIC current call');
    expect(API.createRecordingRelationshipActivity).not.toHaveBeenCalled();
  });

  it.each([
    { account_id: '2' },
    { user_id: '99' },
    { time_zone: null },
    { recording_id: '18' },
    { call_session_id: '19' },
    { call_id: 'SYNTHETIC different call' },
    { contact_id: '20' },
    { origin_revision: false },
  ])(
    'rejects a mismatched or malformed native preview %j without showing its portfolio or granting access',
    async extra => {
      API.recordingRelationshipActivities.mockResolvedValue({
        data: preview(extra),
      });
      const wrapper = setup();
      await open(wrapper);
      expect(
        wrapper.find('[data-recording-relationship-portfolio]').exists()
      ).toBe(false);
      expect(wrapper.text()).not.toContain('SYNTHETIC permitted portfolio');
      expect(wrapper.get('[role="alert"]').text()).toContain(
        'RECORDING_RELATIONSHIP.ERROR'
      );
      expect(API.createRecordingRelationshipActivity).not.toHaveBeenCalled();
    }
  );

  it('keeps read-visible but non-writable native portfolio choices disabled', async () => {
    API.recordingRelationshipActivities.mockResolvedValue({
      data: preview({
        items: [{ id: '33', label: 'SYNTHETIC read only', can_work: false }],
      }),
    });
    const wrapper = setup();
    await open(wrapper);
    expect(
      wrapper.get('option[value="33"]').attributes('disabled')
    ).toBeDefined();
    expect(API.createRecordingRelationshipActivity).not.toHaveBeenCalled();
  });

  it('uses native field values, origin revision and the same owned UUID, blocking concurrent clicks', async () => {
    let resolve;
    API.createRecordingRelationshipActivity.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = setup();
    await open(wrapper);
    await fill(wrapper);
    await wrapper.get('form').trigger('submit');
    await wrapper.get('form').trigger('submit');
    expect(API.createRecordingRelationshipActivity).toHaveBeenCalledTimes(1);
    expect(API.createRecordingRelationshipActivity.mock.calls[0]).toEqual([
      '1',
      '8',
      {
        assignment_id: '33',
        title: 'SYNTHETIC reviewed call activity',
        due_at: '2026-11-30T13:00:00.000Z',
        origin_revision: 'a'.repeat(64),
        request_id: expect.stringMatching(/^[0-9a-f-]{36}$/),
      },
    ]);
    resolve({ data: receipt() });
    await flushPromises();
    expect(
      wrapper.get('[data-recording-relationship-receipt]').text()
    ).toContain('44');
    expect(
      wrapper.getComponent('[data-recording-relationship-target]').props('to')
    ).toEqual({
      name: 'crm_activities',
      params: { accountId: '1' },
      query: { activityId: '44' },
    });
    expect(wrapper.emitted('changed')).toHaveLength(1);
  });

  it('retains an uncertain submission and retries exactly the same request without editing or a new UUID', async () => {
    API.createRecordingRelationshipActivity.mockRejectedValueOnce({
      response: { status: 503 },
    });
    const wrapper = setup();
    await open(wrapper);
    await fill(wrapper);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    const first = API.createRecordingRelationshipActivity.mock.calls[0];
    expect(
      wrapper.get('[data-native-relationship-activity-title]').element.value
    ).toBe('SYNTHETIC reviewed call activity');
    expect(
      wrapper.get('[data-native-relationship-activity-title]').element.disabled
    ).toBe(true);
    expect(
      wrapper.get('[data-recording-relationship-portfolio]').element.disabled
    ).toBe(true);
    expect(wrapper.find('[data-recording-relationship-receipt]').exists()).toBe(
      false
    );
    await wrapper.get('[data-retry-recording-relationship]').trigger('click');
    await flushPromises();
    expect(API.createRecordingRelationshipActivity.mock.calls[1]).toEqual(
      first
    );
    expect(wrapper.find('[data-recording-relationship-receipt]').exists()).toBe(
      true
    );
  });

  it('does not claim success for a malformed or mismatched write receipt', async () => {
    API.createRecordingRelationshipActivity.mockResolvedValueOnce({
      data: receipt({ recording_id: '88' }),
    });
    const wrapper = setup();
    await open(wrapper);
    await fill(wrapper);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.find('[data-recording-relationship-receipt]').exists()).toBe(
      false
    );
    expect(wrapper.get('[data-retry-recording-relationship]').exists()).toBe(
      true
    );
    expect(wrapper.emitted('changed')).toBeUndefined();
  });

  it('forgets private fields and receipts immediately after a native profile change', async () => {
    const wrapper = setup();
    await open(wrapper);
    await fill(wrapper);
    mocks.actor.value.accounts[0].permissions = [];
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC permitted portfolio');
    expect(API.createRecordingRelationshipActivity).not.toHaveBeenCalled();
  });

  it('discards an old preview after switching the account and recording context', async () => {
    let resolve;
    API.recordingRelationshipActivities.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = setup();
    await wrapper.get('[data-open-recording-relationship]').trigger('click');
    await wrapper.setProps({
      accountId: '2',
      recordingId: '18',
      callSessionId: '19',
    });
    resolve({ data: preview() });
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC permitted portfolio');
    expect(API.createRecordingRelationshipActivity).not.toHaveBeenCalled();
  });

  it('withholds the native target link when current destination read permission is unavailable', async () => {
    API.createRecordingRelationshipActivity.mockResolvedValueOnce({
      data: receipt({ target: null }),
    });
    const wrapper = setup();
    await open(wrapper);
    await fill(wrapper);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(
      wrapper.get('[data-recording-relationship-receipt]').text()
    ).toContain('44');
    expect(wrapper.find('[data-recording-relationship-target]').exists()).toBe(
      false
    );
  });
});
