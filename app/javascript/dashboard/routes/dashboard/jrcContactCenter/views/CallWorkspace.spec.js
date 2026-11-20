import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import CallWorkspace from './CallWorkspace.vue';
import LinkedContactMaster from '../components/LinkedContactMaster.vue';
import VisualStatusBadge from '../components/visual/VisualStatusBadge.vue';

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
  it('renders the existing translated native state rather than the backend code', async () => {
    const wrapper = mount(CallWorkspace, {
      props: { accountId: 1, callId: 10 },
    });
    await flushPromises();
    expect(wrapper.getComponent(VisualStatusBadge).props('label')).toBe(
      'JRC_CONTACT_CENTER.INBOX_360.CALL_STATES.connected'
    );
  });

  it('translates the non-compact native call-leg status while preserving the queue and backend state', async () => {
    JrcContactCenterAPI.call.mockResolvedValueOnce({
      data: {
        item: {
          id: 10,
          status: 'connected',
          journey: { legs: [{ id: 7, status: 'connected', queue_id: 44 }] },
        },
      },
    });
    const wrapper = mount(CallWorkspace, {
      props: { accountId: 1, callId: 10 },
    });
    await flushPromises();
    const detail = wrapper
      .findAll('p')
      .map(node => node.text())
      .find(text => text.includes('JRC_CONTACT_CENTER.ADMIN.QUEUE 44'));
    expect(detail).toBe(
      'JRC_CONTACT_CENTER.INBOX_360.CALL_STATES.connected · JRC_CONTACT_CENTER.ADMIN.QUEUE 44'
    );
    expect(wrapper.emitted('loaded').at(-1)[0].call.status).toBe('connected');
  });

  it('keeps the authorized attendance and notes identity when customer lookup is unavailable', async () => {
    JrcContactCenterAPI.customerContext.mockRejectedValueOnce({
      response: { status: 503 },
    });
    const wrapper = mount(CallWorkspace, {
      props: { accountId: 1, callId: 10, compact: true },
    });
    await flushPromises();
    expect(wrapper.emitted('loaded').at(-1)[0]).toMatchObject({
      call: { id: 10, status: 'connected' },
      customer: null,
      customerStatus: 'error',
    });
  });

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

describe('native master updates inside an attendance draft', () => {
  const customer = name => ({
    status: 'identified',
    ambiguous: false,
    directory: { contact_id: '2' },
    contacts: [{ id: '2', name }],
  });
  const payload = name => ({
    data: {
      item: {
        id: 10,
        contact_id: 2,
        direction: 'inbound',
        ani: '+5511999999999',
        status: 'connected',
        customer: customer(name),
      },
    },
  });
  const render = () =>
    mount(CallWorkspace, {
      props: {
        accountId: '1',
        callId: 10,
        context: {
          capabilities: { operate: true },
          provider: { capabilities: {} },
        },
      },
      global: { stubs: { RouterLink: true } },
    });
  beforeEach(() => {
    vi.clearAllMocks();
    JrcContactCenterAPI.call.mockResolvedValue(payload('SYNTHETIC previous'));
    JrcContactCenterAPI.agentState.mockResolvedValue({
      data: { item: { account_user_id: 20 } },
    });
  });

  it('reloads confirmed contact values without clearing the attendance draft or sending a case', async () => {
    const wrapper = render();
    await flushPromises();
    await wrapper
      .get('textarea[aria-label="JRC_CONTACT_CENTER.OCCURRENCES.SUMMARY"]')
      .setValue('SYNTHETIC unsaved attendance');
    JrcContactCenterAPI.call.mockResolvedValueOnce(
      payload('SYNTHETIC updated')
    );
    wrapper.findComponent(LinkedContactMaster).vm.$emit('updated');
    await flushPromises();
    expect(wrapper.text()).toContain('SYNTHETIC updated');
    expect(wrapper.emitted('loaded').at(-1)[0].customer.contacts[0].name).toBe(
      'SYNTHETIC updated'
    );
    expect(
      wrapper.get(
        'textarea[aria-label="JRC_CONTACT_CENTER.OCCURRENCES.SUMMARY"]'
      ).element.value
    ).toBe('SYNTHETIC unsaved attendance');
    expect(JrcContactCenterAPI.createCase).not.toHaveBeenCalled();
  });

  it('clears the old customer and shows an error when the authorized refresh fails, preserving unsaved text', async () => {
    const wrapper = render();
    await flushPromises();
    await wrapper
      .get('textarea[aria-label="JRC_CONTACT_CENTER.OCCURRENCES.SUMMARY"]')
      .setValue('SYNTHETIC preserved');
    JrcContactCenterAPI.call.mockRejectedValueOnce({
      response: { status: 403 },
    });
    wrapper.findComponent(LinkedContactMaster).vm.$emit('updated');
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC previous');
    expect(wrapper.emitted('loaded').at(-1)[0].customer).toBeNull();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'JRC_CONTACT_CENTER.COMMON.ERROR'
    );
    expect(
      wrapper.get(
        'textarea[aria-label="JRC_CONTACT_CENTER.OCCURRENCES.SUMMARY"]'
      ).element.value
    ).toBe('SYNTHETIC preserved');
  });

  it('ignores an old account refresh after navigation to another attendance', async () => {
    const wrapper = render();
    await flushPromises();
    let resolve;
    JrcContactCenterAPI.call.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    wrapper.findComponent(LinkedContactMaster).vm.$emit('updated');
    JrcContactCenterAPI.call.mockResolvedValueOnce(
      payload('SYNTHETIC current account')
    );
    await wrapper.setProps({ accountId: '9', callId: 11 });
    await flushPromises();
    resolve(payload('SYNTHETIC obsolete account'));
    await flushPromises();
    expect(wrapper.text()).toContain('SYNTHETIC current account');
    expect(wrapper.text()).not.toContain('SYNTHETIC obsolete account');
  });
});

describe('phone candidates are not confirmed call links', () => {
  const candidate = {
    status: 'identified',
    identity_source: 'phone_candidates',
    ambiguous: false,
    contacts: [{ id: '77', name: 'SYNTHETIC possible contact' }],
  };
  const payload = customer => ({
    data: {
      item: {
        id: 10,
        contact_id: null,
        direction: 'inbound',
        ani: '+5511999999999',
        status: 'connected',
        customer,
      },
    },
  });
  const render = () =>
    mount(CallWorkspace, {
      props: {
        accountId: '1',
        callId: 10,
        context: { capabilities: { operate: true } },
      },
      global: { stubs: { RouterLink: true } },
    });

  beforeEach(() => {
    vi.clearAllMocks();
    JrcContactCenterAPI.call.mockResolvedValue(payload(candidate));
    JrcContactCenterAPI.agentState.mockResolvedValue({
      data: { item: { account_user_id: '20' } },
    });
    JrcContactCenterAPI.createCase.mockResolvedValue({ data: { item: {} } });
  });

  it('labels a unique phone candidate without opening the native master or replacing the legacy API status', async () => {
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[data-customer-phone-candidate]').text()).toBe(
      'JRC_CONTACT_CENTER.CALL.PHONE_CANDIDATE'
    );
    expect(wrapper.find('[data-open-linked-master]').exists()).toBe(false);
    expect(wrapper.emitted('loaded').at(-1)[0]).toMatchObject({
      call: { contact_id: null },
      customer: { status: 'identified', identity_source: 'phone_candidates' },
    });
    expect(JrcContactCenterAPI.customerContext).not.toHaveBeenCalled();
  });

  it('preserves the original unlinked call when saving an occurrence despite a unique telephone match', async () => {
    const wrapper = render();
    await flushPromises();
    await wrapper
      .get('input[aria-label="JRC_CONTACT_CENTER.CALL.CATEGORY"]')
      .setValue('SYNTHETIC');
    await wrapper
      .get('textarea[aria-label="JRC_CONTACT_CENTER.OCCURRENCES.SUMMARY"]')
      .setValue('SYNTHETIC attendance');
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'JRC_CONTACT_CENTER.CALL.CREATE_CASE')
      .trigger('click');
    await flushPromises();
    expect(JrcContactCenterAPI.createCase).toHaveBeenCalledTimes(1);
    expect(JrcContactCenterAPI.createCase).toHaveBeenCalledWith('1', {
      call_session_id: 10,
      contact_id: undefined,
      owner_account_user_id: '20',
      channel: 'phone',
      category: 'SYNTHETIC',
      summary: 'SYNTHETIC attendance',
    });
    expect(wrapper.get('[data-customer-phone-candidate]').exists()).toBe(true);
    expect(wrapper.find('[data-open-linked-master]').exists()).toBe(false);
  });

  it('clears the phone candidate immediately on navigation and ignores a late response from the previous call', async () => {
    const wrapper = render();
    await flushPromises();
    expect(wrapper.find('[data-customer-phone-candidate]').exists()).toBe(true);
    let resolvePrevious;
    JrcContactCenterAPI.call.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolvePrevious = resolve;
        })
    );
    await wrapper.setProps({ callId: 11 });
    expect(wrapper.find('[data-customer-phone-candidate]').exists()).toBe(
      false
    );
    const linked = payload({
      ...candidate,
      identity_source: 'call_contact_link',
      directory: { contact_id: '77' },
    });
    linked.data.item.id = 12;
    linked.data.item.contact_id = 77;
    JrcContactCenterAPI.call.mockResolvedValueOnce(linked);
    await wrapper.setProps({ accountId: '9', callId: 12 });
    await flushPromises();
    resolvePrevious(payload(candidate));
    await flushPromises();
    expect(wrapper.find('[data-customer-phone-candidate]').exists()).toBe(
      false
    );
    expect(wrapper.emitted('loaded').at(-1)[0]).toMatchObject({
      call: { id: 12, contact_id: 77 },
      customer: { identity_source: 'call_contact_link' },
    });
    expect(wrapper.findComponent(LinkedContactMaster).props('accountId')).toBe(
      '9'
    );
  });
});
