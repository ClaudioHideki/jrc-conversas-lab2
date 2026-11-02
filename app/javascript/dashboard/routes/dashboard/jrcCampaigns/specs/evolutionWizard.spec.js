import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import CampaignWizard from '../components/CampaignWizard.vue';
import api from 'dashboard/api/jrcCampaigns';
import { useAlert } from 'dashboard/composables';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => ({ params: { accountId: '1' } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: {
    audiencePreview: vi.fn(),
    testMessage: vi.fn(),
    testDelivery: vi.fn(),
  },
}));

describe('Evolution campaign test confirmation', () => {
  let wrapper;
  beforeEach(() => {
    vi.clearAllMocks();
    api.audiencePreview.mockResolvedValue({
      data: { estimated_recipients: 1, sample: [] },
    });
    api.testMessage.mockResolvedValue({
      data: { test_delivery_id: 7, message_id: 'provider-id', status: 'sent' },
    });
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    wrapper = mount(CampaignWizard, {
      props: {
        metadata: {
          whatsapp_inboxes: [
            {
              id: 8,
              name: 'WhatsApp Demo',
              connector: 'evolution',
              phone_number: '551155550000',
              min_interval_seconds: 60,
            },
          ],
          source_inboxes: [],
        },
        campaign: {
          id: 1,
          name: 'QA',
          campaign_inboxes: [{ inbox_id: 8, enabled: true }],
          steps: [{ kind: 'text', body: 'Teste', position: 0 }],
        },
      },
      global: {
        mocks: { $t: key => key },
        plugins: [
          createStore({
            getters: {
              'accounts/isFeatureEnabledonAccount': () => () => false,
              'accounts/getAccount': () => () => ({ id: 1 }),
            },
          }),
        ],
      },
    });
    wrapper.vm.testDestination = '5511999999000';
  });
  afterEach(() => {
    wrapper.unmount();
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it('does not send when the operator declines confirmation', async () => {
    window.confirm.mockReturnValue(false);
    await wrapper.vm.sendTest();
    expect(api.testMessage).not.toHaveBeenCalled();
  });

  it('selects the Broker inbox and preserves one test key while the actual provider result is pending', async () => {
    await wrapper.setProps({
      metadata: {
        whatsapp_inboxes: [
          {
            id: 8,
            name: 'Synthetic Broker QR',
            connector: 'broker',
            phone_number: '•••• 0000',
            health_status: 'CONNECTED',
          },
        ],
      },
    });
    api.testMessage.mockResolvedValue({
      data: { test_delivery_id: 9, status: 'sending' },
    });
    await wrapper.vm.sendTest();
    const first = api.testMessage.mock.calls[0][0];
    await wrapper.vm.sendTest();
    expect(first).toMatchObject({ inbox_id: 8, operator_confirmed: true });
    expect(api.testMessage.mock.calls[1][0].idempotency_key).toBe(
      first.idempotency_key
    );
    expect(window.confirm).toHaveBeenCalledWith(
      'JRC_CAMPAIGNS.BROKER.CONFIRM_TEST'
    );
    expect(useAlert).toHaveBeenCalledWith('JRC_CAMPAIGNS.BROKER.TEST_QUEUED');
    expect(useAlert).not.toHaveBeenCalledWith('JRC_CAMPAIGNS.ALERTS.TEST_SENT');
  });

  it('explains an unavailable sender and does not allow selecting it', async () => {
    await wrapper.setProps({
      metadata: {
        whatsapp_inboxes: [
          {
            id: 9,
            name: 'Synthetic QR',
            connector: 'broker',
            health_status: 'DISCONNECTED',
            health_error: true,
            setup_reason: 'CAMPAIGN_IDENTITY_NOT_READY',
          },
        ],
      },
    });
    wrapper.vm.stepIndex = 1;
    await flushPromises();
    const label = wrapper
      .findAll('label')
      .find(item => item.text().includes('Synthetic QR'));
    expect(label.find('input').element.disabled).toBe(true);
    expect(wrapper.text()).toContain(
      'JRC_CAMPAIGNS.BROKER.REASONS.CAMPAIGN_IDENTITY_NOT_READY'
    );
    expect(api.testMessage).not.toHaveBeenCalled();
  });

  it('shows a safe fallback for unknown sender problems without exposing the raw response', async () => {
    await wrapper.setProps({
      metadata: {
        whatsapp_inboxes: [
          {
            id: 9,
            name: 'Synthetic sender',
            connector: 'broker',
            health_status: 'DISCONNECTED',
            health_error: true,
            setup_reason: 'PRIVATE_REMOTE_DIAGNOSTIC',
          },
        ],
      },
    });
    wrapper.vm.stepIndex = 1;
    await flushPromises();
    expect(wrapper.text()).toContain('JRC_CAMPAIGNS.WIZARD.SENDER_UNAVAILABLE');
    expect(wrapper.text()).not.toContain('PRIVATE_REMOTE_DIAGNOSTIC');
    expect(api.testMessage).not.toHaveBeenCalled();
  });

  it('refreshes eligibility from Review after registering consent without sending or launching', async () => {
    wrapper.vm.stepIndex = 3;
    await flushPromises();
    api.audiencePreview.mockResolvedValueOnce({
      data: { estimated_recipients: 2, sample: [] },
    });
    const calls = api.audiencePreview.mock.calls.length;
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'JRC_CAMPAIGNS.CONSENT_IMPORT.REFRESH')
      .trigger('click');
    await flushPromises();
    expect(api.audiencePreview.mock.calls.length).toBe(calls + 1);
    expect(wrapper.vm.eligibleCount).toBe(2);
    expect(api.testMessage).not.toHaveBeenCalled();
    expect(wrapper.emitted('launch')).toBeUndefined();
  });

  it('preserves a configured media message when the sender selection changes', async () => {
    wrapper.vm.form.steps[0] = {
      ...wrapper.vm.form.steps[0],
      kind: 'image',
      body: '',
      media_url: 'https://media.example.test/image.png',
    };
    wrapper.vm.form.inboxLinks = [];
    await flushPromises();
    wrapper.vm.form.inboxLinks = [{ inbox_id: 8, enabled: true }];
    await flushPromises();
    expect(wrapper.vm.form.steps[0].kind).toBe('image');
  });

  it('reuses the idempotency key and displays accepted rather than delivered', async () => {
    await wrapper.vm.sendTest();
    await wrapper.vm.sendTest();
    const first = api.testMessage.mock.calls[0][0];
    const second = api.testMessage.mock.calls[1][0];
    expect(first).toMatchObject({
      inbox_id: 8,
      phone_number: '5511999999000',
      operator_confirmed: true,
    });
    expect(second.idempotency_key).toBe(first.idempotency_key);
    expect(useAlert).toHaveBeenCalledWith(
      'JRC_CAMPAIGNS.EVOLUTION.TEST_ACCEPTED'
    );
    await flushPromises();
    expect(wrapper.text()).toContain('JRC_CAMPAIGNS.EVOLUTION.TEST_RESULT');
  });

  it('does not tell the operator an unknown result was sent', async () => {
    api.testMessage.mockResolvedValue({
      data: { test_delivery_id: 7, status: 'unknown' },
    });
    await wrapper.vm.sendTest();
    expect(useAlert).toHaveBeenCalledWith(
      'JRC_CAMPAIGNS.EVOLUTION.TEST_UNCONFIRMED'
    );
    expect(useAlert).not.toHaveBeenCalledWith('JRC_CAMPAIGNS.ALERTS.TEST_SENT');
  });

  it('prepares a fresh request after an accepted test and the configured interval', async () => {
    vi.useFakeTimers();
    await wrapper.vm.sendTest();
    const firstKey = api.testMessage.mock.calls[0][0].idempotency_key;
    wrapper.vm.prepareNewTest();
    expect(wrapper.vm.latestTest.id).toBe(7);
    await vi.advanceTimersByTimeAsync(61000);
    wrapper.vm.prepareNewTest();
    expect(wrapper.vm.latestTest).toBeNull();
    expect(api.testMessage).toHaveBeenCalledOnce();
    await wrapper.vm.sendTest();
    expect(api.testMessage.mock.calls[1][0].idempotency_key).not.toBe(firstKey);
  });

  it('does not prepare another request for an unknown result', async () => {
    api.testMessage.mockResolvedValue({
      data: { test_delivery_id: 7, status: 'unknown' },
    });
    await wrapper.vm.sendTest();
    wrapper.vm.prepareNewTest();
    expect(wrapper.vm.latestTest.status).toBe('unknown');
    expect(api.testMessage).toHaveBeenCalledOnce();
  });

  it('sends from the Review button independently of campaign audience size', async () => {
    wrapper.vm.stepIndex = 3;
    wrapper.vm.audiencePreview = { estimated_recipients: 0, sample: [] };
    await flushPromises();
    const button = wrapper
      .findAll('button')
      .find(item => item.text() === 'JRC_CAMPAIGNS.WIZARD.SEND_TEST');
    await button.trigger('click');
    await flushPromises();
    expect(api.testMessage).toHaveBeenCalledOnce();
    expect(api.testMessage.mock.calls[0][0].phone_number).toBe('5511999999000');
    expect(wrapper.vm.latestTest.status).toBe('sent');
    expect(wrapper.vm.newTestCoolingDown).toBe(true);
    const updatedButtons = wrapper
      .findAll('button')
      .filter(item => item.text() === 'JRC_CAMPAIGNS.WIZARD.SEND_TEST');
    expect(updatedButtons).toHaveLength(2);
    expect(updatedButtons.every(item => item.element.disabled)).toBe(true);
  });
});
