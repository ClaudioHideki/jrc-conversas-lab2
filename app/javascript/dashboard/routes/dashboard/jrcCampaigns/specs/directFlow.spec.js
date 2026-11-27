import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import CampaignWizard from '../components/CampaignWizard.vue';
import CampaignPerformanceChart from '../components/CampaignPerformanceChart.vue';
import api from 'dashboard/api/jrcCampaigns';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/routes/dashboard/jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ enabled: false }),
}));
vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: { audiencePreview: vi.fn(), create: vi.fn(), launch: vi.fn() },
}));
vi.mock('vue-chartjs', () => ({
  Line: {
    name: 'Line',
    props: ['data', 'options'],
    template: '<div data-chart />',
  },
}));
enableAutoUnmount(afterEach);
const metadata = {
  account_timezone: 'America/Sao_Paulo',
  timezones: ['UTC', 'America/New_York'],
  source_inboxes: [],
  whatsapp_inboxes: [{ id: 8, connector: 'official' }],
};

describe('simplified campaign flow', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.audiencePreview.mockResolvedValue({
      data: { estimated_recipients: 4, sample: [] },
    });
    document.body.classList.remove('dark');
  });
  afterEach(() => document.body.classList.remove('dark'));

  it('uses Sao Paulo for new schedules without a timezone selector or master customer filter', async () => {
    const wrapper = mount(CampaignWizard, {
      props: { metadata },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    expect(wrapper.findComponent({ name: 'ConsentPanel' }).exists()).toBe(
      false
    );
    wrapper.vm.stepIndex = 1;
    await flushPromises();
    expect(wrapper.findComponent({ name: 'CampaignFilters' }).exists()).toBe(
      false
    );
    expect(
      wrapper.get('[data-testid="campaign-timezone"]').find('select').exists()
    ).toBe(false);
    expect(wrapper.vm.form.sending_window.timezone).toBe('America/Sao_Paulo');
    wrapper.vm.form.trigger_type = 'scheduled';
    wrapper.vm.form.scheduled_at = '2026-11-26T09:00';
    expect(wrapper.vm.buildPayload().scheduled_at).toBe(
      '2026-11-26T12:00:00.000Z'
    );
    expect(api.create).not.toHaveBeenCalled();
    expect(api.launch).not.toHaveBeenCalled();
  });

  it('preserves an existing campaign timezone and absolute scheduled time when reopening it', async () => {
    const wrapper = mount(CampaignWizard, {
      props: {
        metadata,
        campaign: {
          id: 17,
          name: 'Existing schedule',
          trigger_type: 'scheduled',
          scheduled_at: '2026-11-26T12:00:00Z',
          sending_window: {
            start: '08:00',
            end: '18:00',
            days: [1],
            timezone: 'America/New_York',
          },
        },
      },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    expect(wrapper.vm.form.sending_window.timezone).toBe('America/New_York');
    expect(wrapper.vm.buildPayload().scheduled_at).toBe(
      '2026-11-26T12:00:00.000Z'
    );
  });

  it('uses the available width and removes manual pacing only for Cloud API senders', async () => {
    const wrapper = mount(CampaignWizard, {
      props: {
        metadata: {
          ...metadata,
          whatsapp_inboxes: [
            { id: 8, provider: 'whatsapp_cloud' },
            { id: 9, provider: 'default' },
          ],
        },
      },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    wrapper.vm.stepIndex = 1;
    wrapper.vm.form.delay_min_seconds = 30;
    wrapper.vm.form.delay_max_seconds = 60;
    wrapper.vm.form.inboxLinks = [{ inbox_id: 8, enabled: true }];
    await flushPromises();
    expect(wrapper.vm.isCloudOnly).toBe(true);
    expect(wrapper.find('[data-testid="campaign-rhythm"]').exists()).toBe(
      false
    );
    expect(wrapper.vm.buildPayload()).toMatchObject({
      delay_min_seconds: 0,
      delay_max_seconds: 0,
    });
    expect(wrapper.vm.durationLabel).toBe(
      'JRC_CAMPAIGNS.WIZARD.CLOUD_DURATION'
    );
    expect(wrapper.get('main > div').classes().join(' ')).not.toContain(
      'max-w-'
    );
    expect(wrapper.get('header h2').classes()).toContain('text-2xl');
    wrapper.vm.form.inboxLinks = [{ inbox_id: 9, enabled: true }];
    await flushPromises();
    expect(wrapper.vm.isCloudOnly).toBe(false);
    expect(wrapper.find('[data-testid="campaign-rhythm"]').exists()).toBe(true);
    expect(wrapper.vm.buildPayload()).toMatchObject({
      delay_min_seconds: 30,
      delay_max_seconds: 60,
    });
  });

  it('keeps chart labels legible when switching between light and dark themes', async () => {
    const wrapper = mount(CampaignPerformanceChart, {
      props: { series: [{ date: '2026-11-26', sent: 4 }], labels: {} },
    });
    const chart = wrapper.getComponent({ name: 'Line' });
    expect(chart.props('options').plugins.legend.labels.color).toBe('#334155');
    expect(chart.props('options').scales.y.ticks.color).toBe('#334155');
    document.body.classList.add('dark');
    await flushPromises();
    expect(chart.props('options').plugins.legend.labels.color).toBe('#cbd5e1');
    expect(chart.props('options').scales.x.ticks.color).toBe('#cbd5e1');
    document.body.classList.remove('dark');
    await flushPromises();
    expect(chart.props('options').plugins.legend.labels.color).toBe('#334155');
  });
});
