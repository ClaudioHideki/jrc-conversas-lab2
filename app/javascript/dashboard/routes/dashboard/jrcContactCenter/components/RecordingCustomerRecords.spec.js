import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import CustomerAPI from 'dashboard/api/jrcCustomers';
import CallCenterAPI from 'dashboard/api/jrcContactCenter';
import RecordingCustomerRecords from './RecordingCustomerRecords.vue';

const native = vi.hoisted(() => ({
  accountId: null,
  identity: null,
  canAccess: null,
}));
vi.mock('../../jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => native,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcCustomers', () => ({
  default: { contactOverview: vi.fn() },
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { call: vi.fn() },
}));
const source = () => ({
  account_id: '1',
  item: {
    id: '15',
    external_session_id: 'SYNTHETIC-call-15',
    contact_id: '33',
    customer: {
      status: 'identified',
      ambiguous: false,
      contacts: [{ id: '33' }],
      directory: { contact_id: '33' },
    },
  },
});
const summary = (rights = {}) => ({
  capabilities: {
    conversations: true,
    crm: true,
    service_desk: true,
    projects: false,
    ...rights,
  },
});
const render = (props = {}) =>
  mount(RecordingCustomerRecords, {
    props: {
      accountId: '1',
      contactId: '33',
      callSessionId: '15',
      callId: 'SYNTHETIC-call-15',
      enabled: true,
      ...props,
    },
    global: {
      stubs: {
        RecordsPanel: {
          name: 'RecordsPanel',
          props: ['contactId', 'kind'],
          template:
            '<div data-native-records-stub>{{ kind }}:{{ contactId }}</div>',
        },
        TimelinePanel: {
          name: 'TimelinePanel',
          props: ['resourceId', 'resourceType'],
          template:
            '<div data-native-timeline-stub>{{ resourceType }}:{{ resourceId }}</div>',
        },
      },
    },
  });
const load = async wrapper => {
  await wrapper.get('[data-load-customer-records]').trigger('click');
  await flushPromises();
};
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  native.accountId = ref('1');
  native.identity = ref('SYNTHETIC actor 4 current account 1');
  native.canAccess = ref(true);
  CallCenterAPI.call.mockResolvedValue({ data: source() });
  CustomerAPI.contactOverview.mockResolvedValue({ data: summary() });
});

describe('recording context reuses current native customer modules', () => {
  it('waits for explicit action, revalidates exact call/directory identity, then opens the existing authorized native list', async () => {
    const wrapper = render();
    expect(CallCenterAPI.call).not.toHaveBeenCalled();
    expect(CustomerAPI.contactOverview).not.toHaveBeenCalled();
    await load(wrapper);
    expect(CallCenterAPI.call).toHaveBeenCalledWith('1', '15');
    expect(CustomerAPI.contactOverview).toHaveBeenCalledWith(
      '33',
      expect.objectContaining({
        accountId: '1',
        signal: expect.any(AbortSignal),
      })
    );
    expect(CallCenterAPI.call.mock.invocationCallOrder[0]).toBeLessThan(
      CustomerAPI.contactOverview.mock.invocationCallOrder[0]
    );
    expect(
      wrapper.getComponent({ name: 'RecordsPanel' }).props()
    ).toMatchObject({ contactId: '33', kind: 'deals' });
  });

  it('reuses native Contracts, Tickets and the signed existing unified timeline without offering private Projects', async () => {
    const wrapper = render();
    await load(wrapper);
    expect(
      wrapper.find('[data-customer-records-tab="projects"]').exists()
    ).toBe(false);
    await wrapper
      .get('[data-customer-records-tab="contracts"]')
      .trigger('click');
    expect(
      wrapper.getComponent({ name: 'RecordsPanel' }).props()
    ).toMatchObject({ contactId: '33', kind: 'contracts' });
    await wrapper.get('[data-customer-records-tab="tickets"]').trigger('click');
    expect(wrapper.getComponent({ name: 'RecordsPanel' }).props('kind')).toBe(
      'tickets'
    );
    await wrapper.get('[data-customer-records-tab="history"]').trigger('click');
    await flushPromises();
    expect(
      wrapper.getComponent({ name: 'TimelinePanel' }).props()
    ).toMatchObject({ resourceId: '33', resourceType: 'contacts' });
    expect(wrapper.findComponent({ name: 'RecordsPanel' }).exists()).toBe(
      false
    );
  });

  it('does not substitute an unavailable CRM or Service Desk module with a fabricated zero', async () => {
    CustomerAPI.contactOverview.mockResolvedValue({
      data: summary({ crm: false, service_desk: false }),
    });
    const wrapper = render();
    await load(wrapper);
    expect(wrapper.findAll('[data-customer-records-tab]')).toHaveLength(1);
    expect(wrapper.findComponent({ name: 'RecordsPanel' }).exists()).toBe(
      false
    );
    expect(
      wrapper.getComponent({ name: 'TimelinePanel' }).props('resourceId')
    ).toBe('33');
  });

  it('offers the native Projects panel only when current native capabilities allow it', async () => {
    CustomerAPI.contactOverview.mockResolvedValueOnce({
      data: summary({ projects: true }),
    });
    const wrapper = render();
    await load(wrapper);
    await wrapper
      .get('[data-customer-records-tab="projects"]')
      .trigger('click');
    expect(
      wrapper.getComponent({ name: 'RecordsPanel' }).props()
    ).toMatchObject({
      contactId: '33',
      kind: 'projects',
    });
  });

  it('does not fetch or mount native customer modules without current directory access or in another account', async () => {
    native.canAccess.value = false;
    const wrapper = render();
    expect(wrapper.find('[data-load-customer-records]').exists()).toBe(false);
    expect(wrapper.text()).toContain('DENIED');
    native.canAccess.value = true;
    native.accountId.value = '2';
    await flushPromises();
    expect(wrapper.find('[data-load-customer-records]').exists()).toBe(false);
    expect(CallCenterAPI.call).not.toHaveBeenCalled();
    expect(CustomerAPI.contactOverview).not.toHaveBeenCalled();
  });

  it.each([
    'different-contact',
    'ambiguous',
    'different-call',
    'different-directory',
  ])(
    'rejects %s source context before reading any customer module',
    async kind => {
      const data = source();
      if (kind === 'different-contact') data.item.contact_id = '34';
      if (kind === 'ambiguous') data.item.customer.ambiguous = true;
      if (kind === 'different-call')
        data.item.external_session_id = 'SYNTHETIC other call';
      if (kind === 'different-directory')
        data.item.customer.directory.contact_id = '34';
      CallCenterAPI.call.mockResolvedValue({ data });
      const wrapper = render();
      await load(wrapper);
      expect(wrapper.get('[role="alert"]').text()).toContain('ERROR');
      expect(CustomerAPI.contactOverview).not.toHaveBeenCalled();
      expect(wrapper.find('[data-native-customer-records]').exists()).toBe(
        false
      );
    }
  );

  it('keeps an actual directory denial visible instead of mounting an empty successful list', async () => {
    CustomerAPI.contactOverview.mockRejectedValueOnce({
      response: { status: 403, data: { error: 'SYNTHETIC private detail' } },
    });
    const wrapper = render();
    await load(wrapper);
    expect(wrapper.get('[role="alert"]').text()).toContain('DENIED');
    expect(wrapper.text()).not.toContain('SYNTHETIC private detail');
    expect(wrapper.find('[data-native-customer-records]').exists()).toBe(false);
    await load(wrapper);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.findComponent({ name: 'RecordsPanel' }).exists()).toBe(true);
  });

  it('discards a late overview after the authenticated membership changes and requires a fresh explicit action', async () => {
    let finish;
    CustomerAPI.contactOverview.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = render();
    await load(wrapper);
    native.identity.value = 'SYNTHETIC different current actor';
    await flushPromises();
    finish({ data: summary({ projects: true }) });
    await flushPromises();
    expect(wrapper.find('[data-native-customer-records]').exists()).toBe(false);
    expect(
      wrapper.find('[data-customer-records-tab="projects"]').exists()
    ).toBe(false);
    expect(CallCenterAPI.call).toHaveBeenCalledTimes(1);
    await load(wrapper);
    expect(CallCenterAPI.call).toHaveBeenCalledTimes(2);
    expect(
      wrapper.find('[data-customer-records-tab="projects"]').exists()
    ).toBe(false);
  });

  it('clears loaded module rows when the native directory feature or access is withdrawn', async () => {
    const wrapper = render();
    await load(wrapper);
    expect(wrapper.find('[data-native-customer-records]').exists()).toBe(true);
    native.canAccess.value = false;
    await flushPromises();
    expect(wrapper.find('[data-native-customer-records]').exists()).toBe(false);
    expect(wrapper.text()).toContain('DENIED');
    native.canAccess.value = true;
    await flushPromises();
    expect(wrapper.find('[data-native-customer-records]').exists()).toBe(false);
  });

  it('rejects malformed native capabilities without interpreting a truthy value as authorization', async () => {
    CustomerAPI.contactOverview.mockResolvedValueOnce({
      data: summary({ projects: 'true' }),
    });
    const wrapper = render();
    await load(wrapper);
    expect(wrapper.get('[role="alert"]').text()).toContain('ERROR');
    expect(wrapper.find('[data-native-customer-records]').exists()).toBe(false);
  });
});
