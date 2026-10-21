import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import ContactAPI from 'dashboard/api/contacts';
import MasterAPI from 'dashboard/api/jrcCustomers';
import { customersAPI } from 'dashboard/api/crm/commercialCycle';
import CCAPI from 'dashboard/api/jrcContactCenter';
import { useInboxCustomer360 } from './useInboxCustomer360';

vi.mock('dashboard/api/contacts', () => ({
  default: {
    get accountIdFromRoute() {
      return window.location.pathname.split('/')[3];
    },
    show: vi.fn(),
  },
}));
vi.mock('dashboard/api/jrcCustomers', () => ({
  default: { contact: vi.fn(), company: vi.fn() },
}));
vi.mock('dashboard/api/crm/commercialCycle', () => ({
  customersAPI: { show: vi.fn() },
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { cases: vi.fn() },
}));
enableAutoUnmount(afterEach);

let identity;
let features;
let state;
const Harness = defineComponent({
  setup() {
    state = useInboxCustomer360(identity, features);
    return () => null;
  },
});

describe('native customer context projection', () => {
  beforeEach(() => {
    window.history.replaceState({}, '', '/app/accounts/1/inbox-view');
    identity = ref({
      accountId: 1,
      contactId: 11,
      conversationId: 101,
      callId: null,
    });
    features = ref({ crm: true, master: true });
    ContactAPI.show.mockResolvedValue({
      data: { payload: { id: 11, name: 'Account A customer' } },
    });
    customersAPI.show.mockResolvedValue({
      data: { orders: [{ id: 1, number: 'A-1' }], timeline: [] },
    });
    CCAPI.cases.mockResolvedValue({
      data: {
        items: [
          { id: 1, contact_id: 11 },
          { id: 2, contact_id: 22 },
        ],
      },
    });
    MasterAPI.contact.mockResolvedValue({
      data: { payload: { company_id: 31 } },
    });
    MasterAPI.company.mockResolvedValue({
      data: {
        payload: { id: 31, name: 'Company A' },
        addresses: [{ city: 'São Paulo' }],
      },
    });
  });

  it('uses native authorized APIs and keeps only cases for the selected identity', async () => {
    mount(Harness);
    await flushPromises();
    expect(ContactAPI.show).toHaveBeenCalledWith(11);
    expect(CCAPI.cases).toHaveBeenCalledWith(1, { limit: 200 });
    expect(state.contact.value.id).toBe(11);
    expect(state.company.value.name).toBe('Company A');
    expect(state.cases.value.map(item => item.id)).toEqual([1]);
    expect(state.crm.value.orders[0].number).toBe('A-1');
  });

  it('does not request optional CRM/master data when their flags are off', async () => {
    features.value = { crm: false, master: false };
    mount(Harness);
    await flushPromises();
    expect(customersAPI.show).not.toHaveBeenCalled();
    expect(MasterAPI.contact).not.toHaveBeenCalled();
    expect(state.contact.value.id).toBe(11);
  });

  it('discards late Account A responses after switching to Account B', async () => {
    let resolveOld;
    ContactAPI.show.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    mount(Harness);
    await flushPromises();
    window.history.replaceState({}, '', '/app/accounts/2/inbox-view');
    ContactAPI.show.mockResolvedValue({
      data: { payload: { id: 22, name: 'B customer' } },
    });
    MasterAPI.contact.mockResolvedValue({ data: { payload: {} } });
    customersAPI.show.mockResolvedValue({ data: { orders: [] } });
    identity.value = { accountId: 2, contactId: 22, conversationId: 202 };
    await flushPromises();
    resolveOld({ data: { payload: { id: 11, name: 'A secret' } } });
    await flushPromises();
    expect(state.contact.value).toEqual({ id: 22, name: 'B customer' });
    expect(state.company.value).toBeNull();
    expect(state.crm.value.orders).toEqual([]);
    expect(MasterAPI.company).not.toHaveBeenCalled();
  });

  it('clears customer state immediately when selection becomes unidentified', async () => {
    mount(Harness);
    await flushPromises();
    identity.value = { accountId: 1, contactId: null, callId: 7 };
    await flushPromises();
    expect(state.contact.value).toBeNull();
    expect(state.company.value).toBeNull();
    expect(state.cases.value).toEqual([]);
    expect(state.loading.value).toBe(false);
  });

  it('discards a late company response after the interaction changes', async () => {
    let resolveCompany;
    MasterAPI.company.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveCompany = resolve;
        })
    );
    mount(Harness);
    await flushPromises();
    identity.value = { accountId: 1, contactId: null, callId: 8 };
    await flushPromises();
    resolveCompany({
      data: { payload: { name: 'Previous customer company' }, addresses: [] },
    });
    await flushPromises();
    expect(state.company.value).toBeNull();
    expect(state.contact.value).toBeNull();
  });

  it('shows partial availability without inventing CRM orders after permission denial', async () => {
    customersAPI.show.mockRejectedValue(new Error('403'));
    mount(Harness);
    await flushPromises();
    expect(state.contact.value.id).toBe(11);
    expect(state.crm.value).toBeNull();
    expect(state.unavailable.value).toBe(true);
    expect(state.failed.value).toBe(false);
  });

  it('does not display related data when contact access is denied', async () => {
    ContactAPI.show.mockRejectedValue(new Error('403'));
    mount(Harness);
    await flushPromises();
    expect(state.failed.value).toBe(true);
    expect(state.crm.value).toBeNull();
    expect(state.cases.value).toEqual([]);
    expect(state.company.value).toBeNull();
  });

  it('does not start requests in a mismatched route account', async () => {
    identity.value.accountId = 2;
    mount(Harness);
    await flushPromises();
    expect(ContactAPI.show).not.toHaveBeenCalled();
    expect(CCAPI.cases).not.toHaveBeenCalled();
  });

  it('invalidates outstanding work on unmount', async () => {
    let resolveOld;
    ContactAPI.show.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = mount(Harness);
    await flushPromises();
    wrapper.unmount();
    resolveOld({ data: { payload: { id: 11, name: 'late' } } });
    await flushPromises();
    expect(state.contact.value).toBeNull();
  });
});
