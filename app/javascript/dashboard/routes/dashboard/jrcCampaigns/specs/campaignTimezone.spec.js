import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import CampaignWizard from '../components/CampaignWizard.vue';
import CampaignApproval from '../components/CampaignApproval.vue';
import api from 'dashboard/api/jrcCampaigns';
import { campaignWindowEstimate } from '../scheduleHelpers';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => `${key} ${JSON.stringify(values || {})}`,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/routes/dashboard/jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ enabled: false }),
}));
vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: { audiencePreview: vi.fn(), requestReview: vi.fn() },
}));
enableAutoUnmount(afterEach);
const global = {
  mocks: { $t: (key, values) => `${key} ${JSON.stringify(values || {})}` },
};

describe('campaign explicit sending timezone', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-10-26T16:49:00Z'));
    api.audiencePreview.mockResolvedValue({
      data: { estimated_recipients: 0, sample: [] },
    });
  });
  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it('keeps a cleared time field editable without an invalid-date render error', async () => {
    const wrapper = mount(CampaignWizard, {
      props: { metadata: { account_timezone: 'America/Sao_Paulo' } },
      global,
    });
    wrapper.vm.form.sending_window.start = '';
    expect(wrapper.vm.nextSendEstimate).toBe('');
  });

  it.each([
    ['2026-03-07T15:00:00Z', '2026-03-08T13:00:00.000Z'],
    ['2026-10-31T15:00:00Z', '2026-11-01T14:00:00.000Z'],
  ])('previews the next local weekday across DST from %s', (base, expected) => {
    const result = campaignWindowEstimate(
      { days: [0], start: '09:00', end: '10:00', timezone: 'America/New_York' },
      new Date(base)
    );
    expect(result.toISOString()).toBe(expected);
  });

  it('automatically signs the account timezone into the payload and shows it beside the window', async () => {
    const wrapper = mount(CampaignWizard, {
      props: { metadata: { account_timezone: 'America/Sao_Paulo' } },
      global,
    });
    wrapper.vm.stepIndex = 1;
    await flushPromises();

    expect(wrapper.vm.buildPayload().sending_window.timezone).toBe(
      'America/Sao_Paulo'
    );
    expect(wrapper.get('[data-campaign-timezone]').text()).toContain(
      'America/Sao_Paulo'
    );
  });

  it.each(['America/Sao_Paulo', 'Asia/Tokyo'])(
    'uses browser %s when account timezone is null',
    async timezone => {
      vi.spyOn(
        Intl.DateTimeFormat.prototype,
        'resolvedOptions'
      ).mockReturnValue({ timeZone: timezone });
      const wrapper = mount(CampaignWizard, {
        props: { metadata: { account_timezone: null } },
        global,
      });
      await flushPromises();
      expect(wrapper.vm.buildPayload().sending_window.timezone).toBe(timezone);
    }
  );

  it.each([
    ['unapproved legacy draft', {}, 'America/Sao_Paulo'],
    [
      'approved legacy draft',
      {
        approved_at: '2026-10-26T15:00:00Z',
        approved_by_id: 9,
        approval_valid: true,
      },
      undefined,
    ],
    [
      'explicit UTC draft',
      {
        sending_window: {
          days: [1],
          start: '08:00',
          end: '18:00',
          timezone: 'UTC',
        },
      },
      'UTC',
    ],
  ])(
    'uses the correct timezone when editing an %s without mutating the saved input',
    async (name, overrides, expected) => {
      const campaign = {
        id: 7,
        status: 'draft',
        sending_window: { days: [1], start: '08:00', end: '18:00' },
        schedule_timezone: 'UTC',
        ...overrides,
      };
      const original = JSON.stringify(campaign);
      const wrapper = mount(CampaignWizard, {
        props: {
          metadata: { account_timezone: 'America/Sao_Paulo' },
          campaign,
        },
        global,
      });
      await flushPromises();
      expect(wrapper.vm.buildPayload().sending_window.timezone).toBe(expected);
      wrapper.vm.stepIndex = 1;
      await flushPromises();
      expect(wrapper.get('[data-campaign-timezone]').text()).toContain(
        expected || 'UTC'
      );
      expect(JSON.stringify(campaign)).toBe(original);
    }
  );

  it.each(['2026-11-01T05:30:00.000Z', '2026-11-01T06:30:00.000Z'])(
    'preserves unchanged scheduled instant %s across a repeated DST wall time',
    async instant => {
      const wrapper = mount(CampaignWizard, {
        props: {
          metadata: {},
          campaign: {
            id: 7,
            trigger_type: 'scheduled',
            scheduled_at: instant,
            sending_window: {
              days: [0],
              start: '00:00',
              end: '23:59',
              timezone: 'America/New_York',
            },
          },
        },
        global,
      });
      await flushPromises();
      expect(wrapper.vm.form.scheduled_at).toBe('2026-11-01T01:30');
      expect(wrapper.vm.buildPayload().scheduled_at).toBe(instant);
    }
  );

  it.each([
    ['new campaign', null, 'America/Sao_Paulo'],
    [
      'explicit UTC',
      {
        id: 7,
        status: 'draft',
        sending_window: {
          days: [1],
          start: '08:00',
          end: '18:00',
          timezone: 'UTC',
        },
      },
      'UTC',
    ],
    [
      'approved legacy',
      {
        id: 7,
        status: 'draft',
        approved_at: '2026-10-26T15:00:00Z',
        sending_window: { days: [1], start: '08:00', end: '18:00' },
      },
      'UTC',
    ],
  ])(
    'handles late account timezone metadata for %s',
    async (name, campaign, expected) => {
      vi.spyOn(
        Intl.DateTimeFormat.prototype,
        'resolvedOptions'
      ).mockReturnValue({ timeZone: 'UTC' });
      const wrapper = mount(CampaignWizard, {
        props: { metadata: {}, campaign },
        global,
      });
      await flushPromises();
      await wrapper.setProps({
        metadata: { account_timezone: 'America/Sao_Paulo' },
      });
      expect(wrapper.vm.form.sending_window.timezone).toBe(expected);
    }
  );

  it('keeps a saved explicit timezone and round trips scheduled wall time in that timezone', async () => {
    const wrapper = mount(CampaignWizard, {
      props: {
        metadata: { account_timezone: 'Asia/Tokyo' },
        campaign: {
          id: 7,
          trigger_type: 'scheduled',
          scheduled_at: '2026-10-26T16:50:00Z',
          sending_window: {
            days: [1],
            start: '13:40',
            end: '14:00',
            timezone: 'America/Sao_Paulo',
          },
        },
      },
      global,
    });
    await flushPromises();
    expect(wrapper.vm.form.scheduled_at).toBe('2026-10-26T13:50');
    expect(wrapper.vm.buildPayload().scheduled_at).toBe(
      '2026-10-26T16:50:00.000Z'
    );
    expect(wrapper.vm.buildPayload().sending_window.timezone).toBe(
      'America/Sao_Paulo'
    );
  });

  it('shows the local next-window estimate instead of silently postponing a week in UTC', async () => {
    const wrapper = mount(CampaignWizard, {
      props: { metadata: { account_timezone: 'America/Sao_Paulo' } },
      global,
    });
    wrapper.vm.form.sending_window = {
      days: [1],
      start: '13:40',
      end: '14:00',
      timezone: 'America/Sao_Paulo',
    };
    wrapper.vm.form.delay_min_seconds = 0;
    wrapper.vm.stepIndex = 1;
    await flushPromises();
    expect(wrapper.get('[data-campaign-eta]').text()).toContain(
      '26/10/2026 13:49'
    );
  });

  it('displays the reviewed timezone and backend estimate before approval', async () => {
    const campaign = {
      id: 7,
      name: 'Synthetic timezone',
      sending_window: {
        days: [1],
        start: '13:40',
        end: '14:00',
        timezone: 'America/Sao_Paulo',
      },
      schedule_timezone: 'America/Sao_Paulo',
      next_send_at: '2026-10-26T16:49:00Z',
      campaign_inboxes: [],
      steps: [],
      delay_min_seconds: 0,
      delay_max_seconds: 0,
      review_snapshot: { configuration: {}, recipients: [] },
    };
    api.requestReview.mockResolvedValue({ data: campaign });
    const wrapper = mount(CampaignApproval, { props: { campaign }, global });
    await flushPromises();
    expect(wrapper.text()).toContain('America/Sao_Paulo');
    expect(wrapper.text()).toContain('26/10/2026 13:49');
  });
});
