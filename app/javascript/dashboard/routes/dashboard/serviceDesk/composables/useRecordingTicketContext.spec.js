import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { defineComponent, reactive, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useRecordingTicketContext } from './useRecordingTicketContext';

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
let route;
let session;
let enabled;
let edit;
let context;
const mountContext = () => {
  wrapper = mount(
    defineComponent({
      setup() {
        context = useRecordingTicketContext({ route, session, enabled, edit });
        return {};
      },
      template: '<div />',
    })
  );
  return flushPromises();
};
beforeEach(() => {
  API.recordingTicketIntake.mockReset().mockResolvedValue({ data: dto() });
  route = reactive({ query: {} });
  session = {
    accountId: ref('1'),
    userId: ref('7'),
    state: reactive({
      status: 'ready',
      context: {
        effective_permissions: ['jrc_service_desk_customers_view'],
        units: [
          {
            id: '10',
            operator_company: { id: '20' },
            permissions: { create_ticket: true },
          },
        ],
      },
    }),
  };
  enabled = ref(true);
  edit = ref(false);
});
afterEach(() => wrapper?.unmount());

it('does not add reads or change ordinary Ticket intake without a selected recording', async () => {
  await mountContext();
  expect(context.present.value).toBe(false);
  expect(API.recordingTicketIntake).not.toHaveBeenCalled();
});
it('loads only the actual selected recording and verifies the native authorized destination', async () => {
  route.query.recording_id = '8';
  await mountContext();
  expect(context.source.value).toEqual(dto());
  expect(API.recordingTicketIntake).toHaveBeenCalledWith('1', '8', {
    signal: expect.any(AbortSignal),
  });
  expect(context.error.value).toBe(false);
});
it.each([null, '', ['8'], '8suffix'])(
  'blocks a malformed selected source without a read or ordinary-intake fallback: %s',
  async value => {
    route.query.recording_id = value;
    await mountContext();
    expect(context.present.value).toBe(true);
    expect(context.source.value).toBeNull();
    expect(context.error.value).toBe(true);
    expect(API.recordingTicketIntake).not.toHaveBeenCalled();
  }
);
it('ignores query parameters that attempt to grant another actor, unit or company', async () => {
  route.query = {
    recording_id: '8',
    user_id: '999',
    unit_id: '999',
    master_company_id: '999',
  };
  await mountContext();
  expect(context.source.value.user_id).toBe('7');
  expect(context.source.value.service_desk_unit_id).toBe('10');
  expect(API.recordingTicketIntake).toHaveBeenCalledTimes(1);
});
it('does not reset the preview or refetch when the same native context is refreshed unchanged', async () => {
  route.query.recording_id = '8';
  await mountContext();
  const previous = context.source.value;
  session.state.context = JSON.parse(JSON.stringify(session.state.context));
  await flushPromises();
  expect(context.source.value).toBe(previous);
  expect(API.recordingTicketIntake).toHaveBeenCalledTimes(1);
});
it('clears a preview and blocks creation immediately after permission withdrawal', async () => {
  route.query.recording_id = '8';
  await mountContext();
  session.state.context.units[0].permissions.create_ticket = false;
  await flushPromises();
  expect(context.source.value).toBeNull();
  expect(context.error.value).toBe(true);
});
it('rejects an old actor preview after profile change even when account and recording match', async () => {
  route.query.recording_id = '8';
  await mountContext();
  session.userId.value = '12';
  await flushPromises();
  expect(context.source.value).toBeNull();
  expect(context.error.value).toBe(true);
});
it('discards a late previous-account response rather than installing it in the new account', async () => {
  let finish;
  API.recordingTicketIntake.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  route.query.recording_id = '8';
  await mountContext();
  session.accountId.value = '2';
  API.recordingTicketIntake.mockResolvedValue({
    data: { ...dto(), account_id: '2' },
  });
  await flushPromises();
  finish({ data: dto() });
  await flushPromises();
  expect(context.source.value.account_id).toBe('2');
});
it('keeps a failed recording context blocked and requires an explicit retry', async () => {
  route.query.recording_id = '8';
  API.recordingTicketIntake.mockRejectedValueOnce({
    response: { status: 403 },
  });
  await mountContext();
  expect(context.present.value).toBe(true);
  expect(context.source.value).toBeNull();
  expect(context.error.value).toBe(true);
  expect(API.recordingTicketIntake).toHaveBeenCalledTimes(1);
  await context.refresh();
  expect(context.source.value).toEqual(dto());
  expect(API.recordingTicketIntake).toHaveBeenCalledTimes(2);
});
it('aborts an outstanding preview on unmount without leaving retained caller data', async () => {
  route.query.recording_id = '8';
  let finish;
  API.recordingTicketIntake.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await mountContext();
  const signal = API.recordingTicketIntake.mock.calls[0][2].signal;
  wrapper.unmount();
  wrapper = null;
  finish({ data: dto() });
  await flushPromises();
  expect(signal.aborted).toBe(true);
  expect(context.source.value).toBeNull();
});
