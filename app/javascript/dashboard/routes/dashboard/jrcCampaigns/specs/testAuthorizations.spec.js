import { flushPromises, mount } from '@vue/test-utils';
import TestAuthorizationPanel from '../components/TestAuthorizationPanel.vue';
import api from 'dashboard/api/jrcCampaigns';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: {
    metadata: vi.fn(),
    testAuthorizations: vi.fn(),
    createTestAuthorization: vi.fn(),
    revokeTestAuthorization: vi.fn(),
  },
}));

describe('Authorization for a single Evolution test', () => {
  let wrapper;
  beforeEach(() => {
    vi.clearAllMocks();
    api.testAuthorizations.mockResolvedValue({ data: [] });
    api.createTestAuthorization.mockResolvedValue({ data: { id: 7 } });
    api.revokeTestAuthorization.mockResolvedValue({});
    api.metadata.mockResolvedValue({
      data: {
        whatsapp_inboxes: [
          {
            id: 8,
            name: 'Demo',
            connector: 'evolution',
            phone_number: '551155550000',
          },
        ],
      },
    });
    wrapper = mount(TestAuthorizationPanel, {
      props: {
        inboxes: [
          {
            id: 8,
            name: 'Demo',
            connector: 'evolution',
            phone_number: '551155550000',
          },
          { id: 1, name: 'Official', phone_number: '551155550001' },
        ],
      },
    });
  });
  afterEach(() => wrapper.unmount());

  it('limits the sender selector to explicitly configured Evolution inboxes', () => {
    expect(wrapper.findAll('option')).toHaveLength(2);
    expect(wrapper.text()).not.toContain('Official');
  });

  it('loads the configured sender when opened inside the consent page', async () => {
    wrapper.unmount();
    wrapper = mount(TestAuthorizationPanel);
    await flushPromises();
    expect(api.metadata).toHaveBeenCalledOnce();
    expect(wrapper.findAll('option')).toHaveLength(2);
    expect(wrapper.find('option[value="8"]').text()).toContain('551155550000');
  });

  it('does not record permission before explicit confirmation', async () => {
    await wrapper.find('select').setValue(8);
    await wrapper
      .find('input:not([type="checkbox"])')
      .setValue('5511999999000');
    await wrapper
      .find('textarea')
      .setValue('Synthetic holder permits a single test.');
    expect(
      wrapper.find('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
    await wrapper.find('form').trigger('submit');
    expect(api.createTestAuthorization).not.toHaveBeenCalled();
  });

  it('records evidence for one destination and sender without invoking a send', async () => {
    await wrapper.find('select').setValue(8);
    await wrapper
      .find('input:not([type="checkbox"])')
      .setValue('5511999999000');
    await wrapper
      .find('textarea')
      .setValue('Synthetic holder permits a single test.');
    await wrapper.find('input[type="checkbox"]').setValue(true);
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(api.createTestAuthorization).toHaveBeenCalledExactlyOnceWith({
      inbox_id: 8,
      phone_number: '5511999999000',
      evidence: 'Synthetic holder permits a single test.',
      operator_confirmed: true,
    });
    expect(wrapper.find('input[type="checkbox"]').element.checked).toBe(false);
  });

  it('shows consumed authorizations without offering to revoke or reuse them', async () => {
    api.testAuthorizations.mockResolvedValue({
      data: [
        {
          id: 7,
          inbox_id: 8,
          phone_number: '+5511999999000',
          sender_number: '551155550000',
          evidence: 'QA',
          consumed_at: '2026-10-20',
          test_delivery_id: 12,
        },
      ],
    });
    await wrapper.vm.load();
    expect(wrapper.text()).toContain(
      'JRC_CAMPAIGNS.TEST_AUTHORIZATION.CONSUMED'
    );
    expect(wrapper.findAll('button')).toHaveLength(1);
  });
});
