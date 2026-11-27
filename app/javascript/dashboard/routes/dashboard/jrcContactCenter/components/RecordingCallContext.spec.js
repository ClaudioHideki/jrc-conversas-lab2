import { afterEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import RecordingCallContext from './RecordingCallContext.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { call: vi.fn() },
}));
const result = () => ({
  account_id: '1',
  item: {
    id: '7',
    external_session_id: 'SYNTHETIC-recorded-call',
    contact_id: '2',
    queue: { name: 'SYNTHETIC native queue' },
    customer: {
      status: 'identified',
      ambiguous: false,
      contacts: [
        {
          id: '2',
          name: 'SYNTHETIC authorized contact',
          company: { id: '9', name: 'SYNTHETIC covered company' },
        },
      ],
      directory: { contact_id: '2' },
    },
  },
});
const render = (props = {}) =>
  mount(RecordingCallContext, {
    props: {
      accountId: '1',
      callSessionId: '7',
      callId: 'SYNTHETIC-recorded-call',
      operationalContextAllowed: true,
      ...props,
    },
    global: {
      stubs: {
        LinkedContactMaster: true,
        RecordingCustomerLink: {
          name: 'RecordingCustomerLink',
          props: [
            'accountId',
            'recordingId',
            'callSessionId',
            'callId',
            'enabled',
          ],
          emits: ['updated'],
          template: '<div data-native-manual-customer-link-stub />',
        },
        RecordingCustomerRecords: {
          name: 'RecordingCustomerRecords',
          props: [
            'accountId',
            'contactId',
            'callSessionId',
            'callId',
            'enabled',
          ],
          template: '<div data-native-customer-records-host-stub />',
        },
      },
    },
  });
enableAutoUnmount(afterEach);
afterEach(() => vi.resetAllMocks());

describe('current native call context inside recording details', () => {
  it('reuses the authenticated existing call API and the native linked-master component', async () => {
    API.call.mockResolvedValue({ data: result() });
    const wrapper = render();
    await flushPromises();
    expect(API.call).toHaveBeenCalledTimes(1);
    expect(API.call).toHaveBeenCalledWith('1', '7');
    expect(wrapper.get('[data-recording-context-contact]').text()).toBe(
      'SYNTHETIC authorized contact'
    );
    expect(wrapper.get('[data-recording-context-company]').text()).toBe(
      'SYNTHETIC covered company'
    );
    expect(
      wrapper.getComponent({ name: 'LinkedContactMaster' }).props()
    ).toMatchObject({
      accountId: '1',
      call: result().item,
      customer: result().item.customer,
      enabled: true,
      showHistory: true,
    });
  });

  it('does not infer a customer from a unique phone candidate or transcript text', async () => {
    const data = result();
    data.item.contact_id = null;
    data.item.metadata = { transcript: 'SYNTHETIC untrusted identity' };
    API.call.mockResolvedValue({ data });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC authorized contact');
    expect(wrapper.text()).not.toContain('SYNTHETIC untrusted identity');
    expect(wrapper.get('[data-recording-context-identity]').text()).toContain(
      'UNLINKED'
    );
    expect(
      wrapper.findComponent({ name: 'LinkedContactMaster' }).exists()
    ).toBe(false);
  });

  it('does not choose the first ambiguous candidate or another explicit contact', async () => {
    const data = result();
    data.item.customer.ambiguous = true;
    API.call.mockResolvedValue({ data });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC authorized contact');
    expect(wrapper.get('[data-recording-context-identity]').text()).toContain(
      'AMBIGUOUS'
    );
    const nextResponse = result();
    nextResponse.item.contact_id = '99';
    API.call.mockResolvedValueOnce({ data: nextResponse });
    await wrapper.setProps({ operationalContextAllowed: false });
    await wrapper.setProps({ operationalContextAllowed: true });
    await flushPromises();
    expect(API.call).toHaveBeenCalledTimes(2);
    expect(
      wrapper.findComponent({ name: 'LinkedContactMaster' }).exists()
    ).toBe(false);
    expect(wrapper.get('[data-recording-context-identity]').text()).toContain(
      'UNLINKED'
    );
  });

  it('clears the customer immediately on authority withdrawal without another API read', async () => {
    API.call.mockResolvedValue({ data: result() });
    const wrapper = render();
    await flushPromises();
    await wrapper.setProps({ operationalContextAllowed: false });
    expect(wrapper.text()).not.toContain('SYNTHETIC authorized contact');
    expect(wrapper.get('[role="alert"]').text()).toContain('RESTRICTED');
    expect(API.call).toHaveBeenCalledTimes(1);
    expect(
      wrapper.findComponent({ name: 'LinkedContactMaster' }).exists()
    ).toBe(false);
  });

  it.each(['account', 'call-session', 'external-call'])(
    'never renders a mismatched %s identity',
    async kind => {
      const data = result();
      if (kind === 'account') data.account_id = '8';
      if (kind === 'call-session') data.item.id = '8';
      if (kind === 'external-call')
        data.item.external_session_id = 'SYNTHETIC-other';
      API.call.mockResolvedValue({ data });
      const wrapper = render();
      await flushPromises();
      expect(wrapper.text()).not.toContain('SYNTHETIC authorized contact');
      expect(wrapper.get('[role="alert"]').text()).toContain('ERROR');
    }
  );

  it('ignores a late response after switching accounts and recordings', async () => {
    let resolveFirst;
    API.call.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveFirst = resolve;
        })
    );
    API.call.mockRejectedValueOnce({ response: { status: 404 } });
    const wrapper = render();
    await wrapper.setProps({
      accountId: '2',
      callSessionId: '8',
      callId: 'SYNTHETIC-other',
    });
    await flushPromises();
    resolveFirst({ data: result() });
    await flushPromises();
    expect(API.call).toHaveBeenLastCalledWith('2', '8');
    expect(wrapper.text()).not.toContain('SYNTHETIC authorized contact');
    expect(wrapper.get('[role="alert"]').text()).toContain('RESTRICTED');
  });

  it('keeps a source failure local and supports an explicit fresh authorized retry', async () => {
    API.call.mockRejectedValueOnce({ response: { status: 503 } });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('ERROR');
    API.call.mockResolvedValueOnce({ data: result() });
    await wrapper.get('[data-recording-context-retry]').trigger('click');
    await flushPromises();
    expect(API.call).toHaveBeenCalledTimes(2);
    expect(wrapper.get('[data-recording-context-contact]').text()).toBe(
      'SYNTHETIC authorized contact'
    );
  });

  it('honors an explicit restricted source and never opens the native directory for it', async () => {
    const data = result();
    data.item.customer.status = 'restricted';
    API.call.mockResolvedValue({ data });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC authorized contact');
    expect(wrapper.get('[data-recording-context-identity]').text()).toContain(
      'RESTRICTED'
    );
    expect(
      wrapper.findComponent({ name: 'LinkedContactMaster' }).exists()
    ).toBe(false);
  });
});

describe('native customer records follow the exact authorized recording contact', () => {
  it('passes the exact original account, call and directory contact to the reused module host', async () => {
    API.call.mockResolvedValue({ data: result() });
    const wrapper = render();
    await flushPromises();
    expect(
      wrapper.getComponent({ name: 'RecordingCustomerRecords' }).props()
    ).toMatchObject({
      accountId: '1',
      contactId: '2',
      callSessionId: '7',
      callId: 'SYNTHETIC-recorded-call',
      enabled: true,
    });
  });

  it('does not open native customer lists when the directory identity differs from the selected call contact', async () => {
    const data = result();
    data.item.customer.directory.contact_id = '99';
    API.call.mockResolvedValue({ data });
    const wrapper = render();
    await flushPromises();
    expect(
      wrapper.findComponent({ name: 'RecordingCustomerRecords' }).exists()
    ).toBe(false);
  });
});

it('offers the manual native-master flow for an unlinked call without treating a phone candidate as an established identity', async () => {
  const data = result();
  data.item.contact_id = null;
  data.item.customer.identity_source = 'phone_candidates';
  API.call.mockResolvedValue({ data });
  const wrapper = render({ recordingId: '8' });
  await flushPromises();
  expect(
    wrapper.getComponent({ name: 'RecordingCustomerLink' }).props()
  ).toMatchObject({
    accountId: '1',
    recordingId: '8',
    callSessionId: '7',
    callId: data.item.external_session_id,
    enabled: true,
  });
  expect(wrapper.findComponent({ name: 'LinkedContactMaster' }).exists()).toBe(
    false
  );
  expect(wrapper.text()).not.toContain('SYNTHETIC authorized contact');
  wrapper.getComponent({ name: 'RecordingCustomerLink' }).vm.$emit('updated');
  await flushPromises();
  expect(API.call).toHaveBeenCalledTimes(2);
});
it('never offers the manual flow as a replacement for an existing explicit call contact', async () => {
  API.call.mockResolvedValue({ data: result() });
  const wrapper = render({ recordingId: '8' });
  await flushPromises();
  expect(
    wrapper.findComponent({ name: 'RecordingCustomerLink' }).exists()
  ).toBe(false);
});
