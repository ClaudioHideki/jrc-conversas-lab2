import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import RecordingPolicyDraftEditor from './RecordingPolicyDraftEditor.vue';

const mocks = vi.hoisted(() => ({ user: null }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.user,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    unitRecordingPolicyDraft: vi.fn(),
    updateUnitRecordingPolicyDraft: vi.fn(),
    queues: vi.fn(),
  },
}));
const Dialog = defineComponent({
  emits: ['close', 'confirm'],
  setup(_props, { expose, emit }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
      close: () => {
        visible.value = false;
        emit('close');
      },
    });
    return { visible, confirm: () => emit('confirm') };
  },
  template:
    '<form v-if="visible" @submit.prevent="confirm"><slot /><slot name="footer" /></form>',
});
const Button = (props, { attrs }) =>
  h(
    'button',
    { ...attrs, type: props.type || 'button', disabled: props.disabled },
    props.label
  );
Button.props = ['label', 'disabled', 'type'];
const policy = () => ({
  scope_snapshot: {
    account_id: '1',
    unit_id: '11',
    issuer_company_id: '31',
    business_unit_id: '41',
  },
  schema_version: 1,
  mode: 'on_demand',
  queue_scope: 'unit',
  queue_ids: [],
  notice: 'SYNTHETIC notice',
  retention_days: null,
});
const response = (draft = policy(), unit = '11') => ({
  data: {
    account_id: '1',
    unit_id: unit,
    draft,
    revision: 'a'.repeat(64),
    applied: false,
    provider_state: 'not_verified',
  },
});
const context = () => ({
  capabilities: { configure: true },
  units: [
    { id: '11', name: 'SYNTHETIC A' },
    { id: '12', name: 'SYNTHETIC B' },
  ],
});
const mountEditor = values =>
  mount(RecordingPolicyDraftEditor, {
    props: { accountId: '1', context: context(), ...values },
    global: { stubs: { Dialog, Button } },
  });
const open = async wrapper => {
  await wrapper.get('[data-open-recording-policy-draft]').trigger('click');
  await wrapper.get('[data-recording-policy-unit]').setValue('11');
  await flushPromises();
};
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.user = ref({
    id: '7',
    accounts: [
      {
        id: '1',
        role: 'agent',
        custom_role_id: '8',
        contact_center_eligible: true,
        permissions: ['jrc_contact_center_configure'],
      },
    ],
  });
  API.unitRecordingPolicyDraft.mockResolvedValue(response());
  API.queues.mockResolvedValue({
    data: {
      account_id: '1',
      items: [{ id: '21', unit_id: '11', name: 'SYNTHETIC Q1' }],
      meta: { page: 1, per_page: 20, pages: 2, total: 21 },
    },
  });
  API.updateUnitRecordingPolicyDraft.mockImplementation(
    (_account, unit, value) =>
      Promise.resolve({
        data: {
          ...response().data,
          unit_id: unit,
          revision: 'b'.repeat(64),
          draft: {
            ...value,
            schema_version: 1,
            scope_snapshot: { ...policy().scope_snapshot, unit_id: unit },
          },
        },
      })
  );
});

describe('Native unit recording policy draft editor', () => {
  it('does not fetch, create or guess a policy until an authorized user selects a unit', async () => {
    const wrapper = mountEditor();
    expect(API.unitRecordingPolicyDraft).not.toHaveBeenCalled();
    await wrapper.get('[data-open-recording-policy-draft]').trigger('click');
    expect(
      wrapper.get('[data-save-recording-policy-draft]').element.disabled
    ).toBe(true);
    expect(API.unitRecordingPolicyDraft).not.toHaveBeenCalled();
    expect(API.updateUnitRecordingPolicyDraft).not.toHaveBeenCalled();
  });

  it('requires explicit mode and scope when no policy has been configured', async () => {
    API.unitRecordingPolicyDraft.mockResolvedValue(response(null));
    const wrapper = mountEditor();
    await open(wrapper);
    expect(wrapper.get('[data-recording-policy-mode]').element.value).toBe('');
    expect(wrapper.get('[data-recording-policy-scope]').element.value).toBe('');
    expect(wrapper.get('[data-recording-policy-retention]').element.value).toBe(
      ''
    );
    expect(
      wrapper.get('[data-save-recording-policy-draft]').element.disabled
    ).toBe(true);
  });

  it('saves through the native unit revision without applying the draft or inventing retention', async () => {
    const wrapper = mountEditor();
    await open(wrapper);
    await wrapper
      .get('[data-recording-policy-notice]')
      .setValue('SYNTHETIC revised');
    await wrapper.get('[data-save-recording-policy-draft]').trigger('click');
    await flushPromises();
    expect(API.updateUnitRecordingPolicyDraft).toHaveBeenCalledExactlyOnceWith(
      '1',
      '11',
      {
        mode: 'on_demand',
        queue_scope: 'unit',
        queue_ids: [],
        notice: 'SYNTHETIC revised',
        retention_days: null,
      },
      'a'.repeat(64)
    );
    expect(wrapper.find('[data-recording-policy-saved]').exists()).toBe(true);
    expect(wrapper.emitted('changed')).toHaveLength(1);
    expect(wrapper.text()).toContain('RECORDING_POLICY_DRAFT.LOCAL_ONLY');
  });

  it('prevents duplicate submits while the native save is in flight', async () => {
    API.updateUnitRecordingPolicyDraft.mockReturnValue(new Promise(() => {}));
    const wrapper = mountEditor();
    await open(wrapper);
    await wrapper.get('form').trigger('submit');
    await wrapper.get('form').trigger('submit');
    expect(API.updateUnitRecordingPolicyDraft).toHaveBeenCalledTimes(1);
    expect(wrapper.get('[data-recording-policy-unit]').element.disabled).toBe(
      true
    );
  });

  it('keeps values after a validation failure for a safe explicit retry', async () => {
    API.updateUnitRecordingPolicyDraft.mockRejectedValue({
      response: { status: 422 },
    });
    const wrapper = mountEditor();
    await open(wrapper);
    await wrapper
      .get('[data-recording-policy-notice]')
      .setValue('SYNTHETIC preserve');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[data-recording-policy-notice]').element.value).toBe(
      'SYNTHETIC preserve'
    );
    expect(
      wrapper.get('[data-save-recording-policy-draft]').element.disabled
    ).toBe(false);
    expect(wrapper.find('[data-recording-policy-saved]').exists()).toBe(false);
  });

  it.each([409, 428, 500, undefined])(
    'requires explicit reload after conflict or uncertain result %s',
    async status => {
      API.updateUnitRecordingPolicyDraft.mockRejectedValue({
        response: { status },
      });
      const wrapper = mountEditor();
      await open(wrapper);
      await wrapper.get('form').trigger('submit');
      await flushPromises();
      expect(
        wrapper.get('[data-save-recording-policy-draft]').element.disabled
      ).toBe(true);
      await wrapper.get('form').trigger('submit');
      expect(API.updateUnitRecordingPolicyDraft).toHaveBeenCalledTimes(1);
      API.unitRecordingPolicyDraft.mockResolvedValue(
        response({ ...policy(), notice: 'SYNTHETIC latest' })
      );
      await wrapper
        .get('[data-reload-recording-policy-draft]')
        .trigger('click');
      await flushPromises();
      expect(wrapper.get('[data-recording-policy-notice]').element.value).toBe(
        'SYNTHETIC latest'
      );
      expect(
        wrapper.get('[data-save-recording-policy-draft]').element.disabled
      ).toBe(false);
    }
  );

  it.each(['0', '-2', '1.5', 'x', '9007199254740992'])(
    'rejects ambiguous retention %s',
    async value => {
      const wrapper = mountEditor();
      await open(wrapper);
      await wrapper.get('[data-recording-policy-retention]').setValue(value);
      await wrapper.get('form').trigger('submit');
      expect(
        wrapper.get('[data-save-recording-policy-draft]').element.disabled
      ).toBe(true);
      expect(API.updateUnitRecordingPolicyDraft).not.toHaveBeenCalled();
    }
  );

  it('loads authorized native queue pages and keeps selections while navigating and searching', async () => {
    const wrapper = mountEditor();
    await open(wrapper);
    await wrapper
      .get('[data-recording-policy-scope]')
      .setValue('selected_queues');
    await flushPromises();
    await wrapper.get('[data-recording-policy-queue="21"]').setValue(true);
    API.queues.mockResolvedValue({
      data: {
        account_id: '1',
        items: [{ id: '22', unit_id: '11', name: 'SYNTHETIC Q2' }],
        meta: { page: 2, per_page: 20, pages: 2, total: 21 },
      },
    });
    await wrapper.get('[data-recording-policy-queue-next]').trigger('click');
    await flushPromises();
    expect(API.queues).toHaveBeenLastCalledWith('1', {
      unit_id: '11',
      page: 2,
      per_page: 20,
      q: '',
    });
    await wrapper.get('[data-recording-policy-queue="22"]').setValue(true);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(
      API.updateUnitRecordingPolicyDraft.mock.calls[0][2].queue_ids
    ).toEqual(['21', '22']);
    expect(wrapper.find('[data-recording-policy-saved]').exists()).toBe(true);
    await wrapper
      .get('[data-remove-recording-policy-queue="21"]')
      .trigger('click');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(
      API.updateUnitRecordingPolicyDraft.mock.calls[1][2].queue_ids
    ).toEqual(['22']);
  });

  it('rejects a queue response from a different unit without showing private names', async () => {
    API.queues.mockResolvedValue({
      data: {
        account_id: '1',
        items: [{ id: '99', unit_id: '12', name: 'SYNTHETIC PRIVATE' }],
        meta: { page: 1, per_page: 20, pages: 1 },
      },
    });
    const wrapper = mountEditor();
    await open(wrapper);
    await wrapper
      .get('[data-recording-policy-scope]')
      .setValue('selected_queues');
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC PRIVATE');
    expect(wrapper.text()).toContain('RECORDING_POLICY_DRAFT.QUEUE_ERROR');
    expect(
      wrapper.get('[data-save-recording-policy-draft]').element.disabled
    ).toBe(true);
  });

  it('removes private values immediately after profile or corporate unit coverage is withdrawn', async () => {
    const wrapper = mountEditor();
    await open(wrapper);
    await wrapper.setProps({
      context: { capabilities: { configure: false }, units: [] },
    });
    expect(wrapper.find('[data-recording-policy-draft]').exists()).toBe(false);
    expect(wrapper.find('[data-open-recording-policy-draft]').exists()).toBe(
      false
    );
    expect(wrapper.text()).not.toContain('SYNTHETIC notice');
  });

  it('does not offer the configuration action to another account or an unauthenticated actor', async () => {
    const wrapper = mountEditor();
    mocks.user.value = { id: '8', accounts: [{ id: '2' }] };
    await flushPromises();
    expect(wrapper.find('[data-open-recording-policy-draft]').exists()).toBe(
      false
    );
    expect(API.unitRecordingPolicyDraft).not.toHaveBeenCalled();
  });

  it('ignores an old unit response after switching units without leaking old draft contents', async () => {
    let resolve;
    API.unitRecordingPolicyDraft
      .mockReturnValueOnce(
        new Promise(done => {
          resolve = done;
        })
      )
      .mockResolvedValueOnce(
        response({ ...policy(), notice: 'SYNTHETIC B' }, '12')
      );
    const wrapper = mountEditor();
    await wrapper.get('[data-open-recording-policy-draft]').trigger('click');
    await wrapper.get('[data-recording-policy-unit]').setValue('11');
    // The UI prevents changing the unit while loading; withdrawal must still invalidate the pending result.
    await wrapper.setProps({
      context: { ...context(), units: [{ id: '12', name: 'SYNTHETIC B' }] },
    });
    resolve(response({ ...policy(), notice: 'SYNTHETIC PRIVATE OLD' }));
    await flushPromises();
    expect(wrapper.find('[data-recording-policy-draft]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC PRIVATE OLD');
  });

  it('does not display a draft with a different stored corporate source identity', async () => {
    API.unitRecordingPolicyDraft.mockResolvedValue(
      response({
        ...policy(),
        scope_snapshot: { ...policy().scope_snapshot, account_id: '2' },
      })
    );
    const wrapper = mountEditor();
    await open(wrapper);
    expect(wrapper.find('[data-recording-policy-notice]').exists()).toBe(false);
    expect(
      wrapper.get('[data-save-recording-policy-draft]').element.disabled
    ).toBe(true);
    expect(wrapper.text()).not.toContain('SYNTHETIC notice');
  });

  it('does not claim success for a changed identity or an incomplete save response', async () => {
    API.updateUnitRecordingPolicyDraft.mockResolvedValue(response(null, '12'));
    const wrapper = mountEditor();
    await open(wrapper);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.find('[data-recording-policy-saved]').exists()).toBe(false);
    expect(
      wrapper.get('[data-save-recording-policy-draft]').element.disabled
    ).toBe(true);
    expect(wrapper.emitted('changed')).toBeUndefined();
  });
});
