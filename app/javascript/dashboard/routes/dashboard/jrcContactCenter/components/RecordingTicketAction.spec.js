import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import RecordingTicketAction from './RecordingTicketAction.vue';

const mocks = vi.hoisted(() => ({ actor: null, push: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: mocks.push }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.actor,
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { recordingTicketIntake: vi.fn() },
}));
const dto = () => ({
  contract_version: 1,
  account_id: '1',
  user_id: '7',
  recording_id: '8',
  call_session_id: '9',
  call_id: 'SYNTHETIC linked native call',
  contact_id: '33',
  service_desk_unit_id: '10',
});
let wrapper;
const render = async (props = {}) => {
  wrapper = mount(RecordingTicketAction, {
    props: {
      accountId: '1',
      recordingId: '8',
      callSessionId: '9',
      callId: dto().call_id,
      contactId: '33',
      enabled: true,
      ...props,
    },
  });
  await flushPromises();
};
beforeEach(() => {
  mocks.actor = ref('7');
  mocks.push.mockReset().mockResolvedValue(undefined);
  API.recordingTicketIntake.mockReset().mockResolvedValue({ data: dto() });
});
afterEach(() => wrapper?.unmount());

it('opens only the existing native form after a fresh authorized preview, without creating a Ticket', async () => {
  await render();
  await wrapper.get('[data-open-native-recording-ticket]').trigger('click');
  await flushPromises();
  expect(API.recordingTicketIntake).toHaveBeenCalledTimes(2);
  expect(mocks.push).toHaveBeenCalledTimes(1);
  expect(mocks.push).toHaveBeenCalledWith({
    name: 'jrc_service_desk_new',
    params: { accountId: '1' },
    query: { recording_id: '8' },
  });
});
it('makes no source request when operational context is unavailable', async () => {
  await render({ enabled: false });
  expect(API.recordingTicketIntake).not.toHaveBeenCalled();
  expect(wrapper.find('[data-open-native-recording-ticket]').exists()).toBe(
    false
  );
});
it.each([
  'account_id',
  'user_id',
  'recording_id',
  'call_session_id',
  'call_id',
  'contact_id',
])(
  'does not show an action for a mismatching source field: %s',
  async field => {
    API.recordingTicketIntake.mockResolvedValue({
      data: { ...dto(), [field]: '999' },
    });
    await render();
    expect(wrapper.find('[data-open-native-recording-ticket]').exists()).toBe(
      false
    );
    expect(mocks.push).not.toHaveBeenCalled();
  }
);
it('does not navigate when access has been revoked between preview and explicit opening', async () => {
  await render();
  API.recordingTicketIntake.mockRejectedValueOnce({
    response: { status: 403 },
  });
  await wrapper.get('[data-open-native-recording-ticket]').trigger('click');
  await flushPromises();
  expect(mocks.push).not.toHaveBeenCalled();
  expect(wrapper.find('[data-open-native-recording-ticket]').exists()).toBe(
    false
  );
  expect(wrapper.get('[role="alert"]').text()).toContain('UNAVAILABLE');
});
it('does not navigate twice while a fresh origin check is pending', async () => {
  await render();
  let finish;
  API.recordingTicketIntake.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const button = wrapper.get('[data-open-native-recording-ticket]');
  await button.trigger('click');
  await button.trigger('click');
  expect(API.recordingTicketIntake).toHaveBeenCalledTimes(2);
  finish({ data: dto() });
  await flushPromises();
  expect(mocks.push).toHaveBeenCalledTimes(1);
});
it('drops a pending source when operational authority changes before its response', async () => {
  let finish;
  API.recordingTicketIntake.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  await wrapper.setProps({ enabled: false });
  finish({ data: dto() });
  await flushPromises();
  expect(wrapper.find('[data-open-native-recording-ticket]').exists()).toBe(
    false
  );
  expect(mocks.push).not.toHaveBeenCalled();
});
it('does not reuse the previous actor preview after an account-local profile change', async () => {
  await render();
  mocks.actor.value = '12';
  await flushPromises();
  expect(wrapper.find('[data-open-native-recording-ticket]').exists()).toBe(
    false
  );
  expect(mocks.push).not.toHaveBeenCalled();
});
