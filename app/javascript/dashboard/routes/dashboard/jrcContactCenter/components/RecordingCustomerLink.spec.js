import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import RecordingCustomerLink from './RecordingCustomerLink.vue';

const mocks = vi.hoisted(() => ({ actor: null, master: null }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.actor,
}));
vi.mock('../../jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => mocks.master,
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { recordingCustomerLink: vi.fn(), linkRecordingCustomer: vi.fn() },
}));
const preview = () => ({
  contract_version: 1,
  account_id: '1',
  user_id: '7',
  recording_id: '8',
  call_session_id: '9',
  call_id: 'SYNTHETIC initial link call',
  lock_version: 3,
  can_link: true,
  already_linked: false,
});
let wrapper;
const render = async (props = {}) => {
  wrapper = mount(RecordingCustomerLink, {
    props: {
      accountId: '1',
      recordingId: '8',
      callSessionId: '9',
      callId: preview().call_id,
      enabled: true,
      ...props,
    },
    global: {
      stubs: {
        ContactPicker: {
          name: 'ContactPicker',
          props: ['modelValue', 'disabled'],
          emits: ['update:modelValue'],
          template: '<div data-native-master-picker />',
        },
        Button: {
          props: ['label', 'disabled', 'type'],
          emits: ['click'],
          template:
            '<button :type="type || \'button\'" :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });
  await flushPromises();
};
const open = async () => {
  await wrapper.get('[data-open-recording-customer-link]').trigger('click');
  await flushPromises();
};
const choose = async () => {
  wrapper
    .getComponent({ name: 'ContactPicker' })
    .vm.$emit('update:modelValue', '33');
  await flushPromises();
};
const confirm = async () => {
  await choose();
  await wrapper.get('[data-confirm-recording-customer-link]').setValue(true);
};
beforeEach(() => {
  mocks.actor = ref('7');
  mocks.master = {
    accountId: ref(1),
    canAccess: ref(true),
    identity: ref('SYNTHETIC current native membership'),
  };
  API.recordingCustomerLink.mockReset().mockResolvedValue({ data: preview() });
  API.linkRecordingCustomer.mockReset();
  API.linkRecordingCustomer.mockResolvedValue({
    data: { ...preview(), contact_id: '33', lock_version: 4 },
  });
});
afterEach(() => wrapper?.unmount());

it('does not search or request a source before the explicit action', async () => {
  await render();
  expect(API.recordingCustomerLink).not.toHaveBeenCalled();
  expect(wrapper.findComponent({ name: 'ContactPicker' }).exists()).toBe(false);
  expect(API.linkRecordingCustomer).not.toHaveBeenCalled();
});
it('opens the existing native master picker only after a fresh exact source preview', async () => {
  await render();
  await open();
  expect(API.recordingCustomerLink).toHaveBeenCalledWith('1', '8', {
    signal: expect.any(AbortSignal),
  });
  expect(wrapper.getComponent({ name: 'ContactPicker' }).props()).toMatchObject(
    { modelValue: null, disabled: false }
  );
  expect(
    wrapper.get('[data-save-recording-customer-link]').attributes('disabled')
  ).toBeDefined();
});
it('requires a selected contact and independent explicit confirmation before the single native write', async () => {
  await render();
  await open();
  await wrapper.get('form').trigger('submit');
  expect(API.linkRecordingCustomer).not.toHaveBeenCalled();
  await choose();
  await wrapper.get('form').trigger('submit');
  expect(API.linkRecordingCustomer).not.toHaveBeenCalled();
  await wrapper.get('[data-confirm-recording-customer-link]').setValue(true);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(API.linkRecordingCustomer).toHaveBeenCalledTimes(1);
  expect(API.linkRecordingCustomer).toHaveBeenCalledWith('1', '8', {
    contact_id: '33',
    call_session_id: '9',
    call_id: preview().call_id,
    lock_version: 3,
    confirm: true,
  });
  expect(wrapper.emitted('updated')).toHaveLength(1);
});
it('does not reuse confirmation when the user chooses another existing person', async () => {
  await render();
  await open();
  await confirm();
  wrapper
    .getComponent({ name: 'ContactPicker' })
    .vm.$emit('update:modelValue', '44');
  await flushPromises();
  expect(
    wrapper.get('[data-confirm-recording-customer-link]').element.checked
  ).toBe(false);
  await wrapper.get('form').trigger('submit');
  expect(API.linkRecordingCustomer).not.toHaveBeenCalled();
});
it.each([
  'account_id',
  'user_id',
  'recording_id',
  'call_session_id',
  'call_id',
])(
  'rejects a mismatching native source %s before opening the directory',
  async field => {
    API.recordingCustomerLink.mockResolvedValue({
      data: { ...preview(), [field]: '999' },
    });
    await render();
    await open();
    expect(wrapper.findComponent({ name: 'ContactPicker' }).exists()).toBe(
      false
    );
    expect(wrapper.get('[role="alert"]').text()).toContain('ERROR');
    expect(API.linkRecordingCustomer).not.toHaveBeenCalled();
  }
);
it('shows no manual-link control when native master access or the requested account is unavailable', async () => {
  mocks.master.canAccess.value = false;
  await render();
  expect(wrapper.find('[data-open-recording-customer-link]').exists()).toBe(
    false
  );
  mocks.master.canAccess.value = true;
  mocks.master.accountId.value = 2;
  await flushPromises();
  expect(wrapper.find('[data-open-recording-customer-link]').exists()).toBe(
    false
  );
  expect(API.recordingCustomerLink).not.toHaveBeenCalled();
});
it('reloads an already linked call rather than offering to replace its origin', async () => {
  API.recordingCustomerLink.mockResolvedValue({
    data: { ...preview(), can_link: false, already_linked: true },
  });
  await render();
  await open();
  expect(wrapper.emitted('updated')).toHaveLength(1);
  expect(wrapper.find('form').exists()).toBe(false);
  expect(API.linkRecordingCustomer).not.toHaveBeenCalled();
});
it('prevents duplicate writes while the first native request remains pending', async () => {
  let resolve;
  API.linkRecordingCustomer.mockImplementation(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  await render();
  await open();
  await confirm();
  await wrapper.get('form').trigger('submit');
  await wrapper.get('form').trigger('submit');
  expect(API.linkRecordingCustomer).toHaveBeenCalledTimes(1);
  resolve({ data: { ...preview(), contact_id: '33', lock_version: 4 } });
  await flushPromises();
  expect(wrapper.emitted('updated')).toHaveLength(1);
});
it.each([409, 422, 503])(
  'preserves selection after HTTP %s but requires current-state verification and another confirmation',
  async status => {
    API.linkRecordingCustomer.mockRejectedValue({ response: { status } });
    await render();
    await open();
    await confirm();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(
      wrapper.getComponent({ name: 'ContactPicker' }).props('modelValue')
    ).toBe('33');
    expect(
      wrapper.get('[data-confirm-recording-customer-link]').element.checked
    ).toBe(false);
    expect(
      wrapper.get('[data-save-recording-customer-link]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(API.linkRecordingCustomer).toHaveBeenCalledTimes(1);
  }
);
it('does not announce success for a mismatching persisted receipt', async () => {
  API.linkRecordingCustomer.mockResolvedValue({
    data: { ...preview(), contact_id: '44', lock_version: 4 },
  });
  await render();
  await open();
  await confirm();
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.emitted('updated')).toBeUndefined();
  expect(wrapper.get('[role="alert"]').text()).toContain('SAVE_ERROR');
});
it('clears directory content after a denial during the actual write', async () => {
  API.linkRecordingCustomer.mockRejectedValue({ response: { status: 403 } });
  await render();
  await open();
  await confirm();
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.findComponent({ name: 'ContactPicker' }).exists()).toBe(false);
  expect(wrapper.get('[role="alert"]').text()).toContain('DENIED');
});
it('discards a pending response and selection when the current user or membership changes', async () => {
  let resolve;
  API.recordingCustomerLink.mockImplementation(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  await render();
  await wrapper.get('[data-open-recording-customer-link]').trigger('click');
  mocks.actor.value = '77';
  mocks.master.identity.value = 'SYNTHETIC changed membership';
  await flushPromises();
  resolve({ data: preview() });
  await flushPromises();
  expect(wrapper.find('form').exists()).toBe(false);
  expect(wrapper.emitted('updated')).toBeUndefined();
});
it('clears the selected person and confirmation when the recording context changes', async () => {
  await render();
  await open();
  await confirm();
  await wrapper.setProps({ recordingId: '18', callSessionId: '19' });
  expect(wrapper.find('form').exists()).toBe(false);
  expect(API.linkRecordingCustomer).not.toHaveBeenCalled();
});
