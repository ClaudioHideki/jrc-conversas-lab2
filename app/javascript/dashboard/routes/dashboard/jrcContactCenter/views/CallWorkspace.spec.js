import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import CallWorkspace from './CallWorkspace.vue';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    call: vi.fn(),
    agentState: vi.fn(),
    customerContext: vi.fn(),
    createCommand: vi.fn(),
    createCase: vi.fn(),
    createCallback: vi.fn(),
  },
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'pt_BR' } }),
}));
enableAutoUnmount(afterEach);

describe('CallWorkspace', () => {
  beforeEach(() => {
    JrcContactCenterAPI.call.mockResolvedValue({
      data: {
        item: {
          id: 10,
          direction: 'inbound',
          ani: '551100000000',
          status: 'connected',
        },
      },
    });
    JrcContactCenterAPI.agentState.mockResolvedValue({
      data: { item: { account_user_id: '20' } },
    });
    JrcContactCenterAPI.customerContext.mockResolvedValue({
      data: { contacts: [] },
    });
  });

  it('blocks provider transfers and keeps the existing webphone closed while capabilities are pending', async () => {
    const wrapper = mount(CallWorkspace, {
      props: {
        accountId: '1',
        callId: 10,
        context: {
          capabilities: { operate: true },
          provider: { capabilities: { sip_webrtc: 'pending_contract' } },
        },
      },
      global: { stubs: { RouterLink: true } },
    });
    await flushPromises();
    await wrapper.find('input').setValue('1001');
    const buttons = wrapper.findAll('button').slice(0, 2);
    expect(
      buttons.every(button => button.attributes('disabled') !== undefined)
    ).toBe(true);
    expect(wrapper.findComponent({ name: 'RouterLink' }).exists()).toBe(false);
    expect(JrcContactCenterAPI.createCommand).not.toHaveBeenCalled();
  });

  it('does not show occurrence or callback mutation controls to read-only users', async () => {
    const wrapper = mount(CallWorkspace, {
      props: {
        accountId: '1',
        callId: 10,
        context: { capabilities: { operate: false } },
      },
      global: { stubs: { RouterLink: true } },
    });
    await flushPromises();
    expect(wrapper.findAll('button')).toHaveLength(0);
    expect(JrcContactCenterAPI.createCase).not.toHaveBeenCalled();
    expect(JrcContactCenterAPI.createCallback).not.toHaveBeenCalled();
  });

  it('embeds the native journey without duplicating customer panels or mutation forms', async () => {
    JrcContactCenterAPI.call.mockResolvedValueOnce({
      data: {
        item: {
          id: 10,
          ani: '551100000000',
          direction: 'inbound',
          status: 'connected',
          journey: {
            legs: [
              {
                id: 7,
                status: 'connected',
                started_at: '2026-10-16T12:00:00Z',
              },
            ],
          },
        },
      },
    });
    const wrapper = mount(CallWorkspace, {
      props: {
        accountId: 1,
        callId: 10,
        compact: true,
        section: 'journey',
        context: { capabilities: { operate: true } },
      },
    });
    await flushPromises();
    expect(wrapper.element.firstElementChild.tagName).not.toBe('HEADER');
    expect(wrapper.find('input').exists()).toBe(false);
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.INBOX_360.AGENT_LEG');
    expect(wrapper.text()).toContain('16/10/2026');
    expect(wrapper.text()).not.toContain('Perna 7');
    expect(wrapper.emitted('loaded').at(-1)[0]).toMatchObject({
      call: { id: 10 },
      customer: { contacts: [] },
      agent: { account_user_id: '20' },
    });
  });

  it('does not emit stale customer context after switching Accounts', async () => {
    let resolveOld;
    JrcContactCenterAPI.customerContext.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = mount(CallWorkspace, {
      props: { accountId: 1, callId: 10 },
    });
    await flushPromises();
    JrcContactCenterAPI.call.mockResolvedValue({
      data: {
        item: {
          id: 20,
          ani: 'ACCOUNT-B',
          direction: 'inbound',
          status: 'connected',
        },
      },
    });
    await wrapper.setProps({ accountId: 2, callId: 20 });
    await flushPromises();
    resolveOld({
      data: { contacts: [{ id: 1, name: 'Account A private context' }] },
    });
    await flushPromises();
    const delivered = wrapper.emitted('loaded').filter(([item]) => item);
    expect(delivered).toHaveLength(1);
    expect(delivered[0][0].call.id).toBe(20);
    expect(delivered[0][0].customer.contacts).toEqual([]);
    expect(wrapper.text()).not.toContain('Account A private context');
  });
});
