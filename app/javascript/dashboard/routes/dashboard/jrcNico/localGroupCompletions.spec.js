import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import HelpdeskGroupPreview from './HelpdeskGroupPreview.vue';
import { helpdeskGroupInput } from './helpdeskPresentation';

const mocks = vi.hoisted(() => ({
  api: { groupPreview: vi.fn(), groupPrepare: vi.fn() },
}));
vi.mock('dashboard/api/jrcNicoHelpdesk', () => ({ default: mocks.api }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const response = (groupKey, ruleKey, overrides = {}) => ({
  contract_version: 1,
  event_id: 8,
  group_key: groupKey,
  enabled: true,
  executable: true,
  preview: true,
  persisted: false,
  automatic_execution: false,
  preview_digest: 'a'.repeat(64),
  source: { ticket_id: 21, unit_id: 3, rule_key: ruleKey },
  evidence: [{ kind: 'Ticket', id: 21 }],
  missing: [],
  required_fields: [],
  attempts: { recorded: 0, limit: 2, handoff_required: false },
  actions: [
    {
      tool: 'add_service_ticket_note',
      arguments: { ticket_id: 21, body: 'Reviewed' },
      can_prepare: true,
    },
  ],
  ...overrides,
});
const page = async (ruleKey = 'R03') => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        name: 'jrc_broker_connections',
        path: '/app/accounts/:accountId/broker',
        component: { template: '<div />' },
      },
    ],
  });
  await router.push('/app/accounts/12/broker');
  await router.isReady();
  const wrapper = mount(HelpdeskGroupPreview, {
    props: {
      accountId: 12,
      contextKey: '12:7:administrator',
      event: { id: 8, ticket_id: 21, rule_key: ruleKey },
      catalog: ['E', 'B2', 'C1', 'C2', 'D2'].map(key => ({ key, name: key })),
    },
    global: { plugins: [router], stubs: { HelpdeskGroupFields: true } },
  });
  return { wrapper, router };
};

beforeEach(() => {
  vi.clearAllMocks();
});

describe('Local HelpDesk group completion through existing preview and approval', () => {
  it.each(['E', 'B2', 'C1'])(
    'includes an explicit query in %s without any automatic lookup or request',
    async groupKey => {
      const { wrapper } = await page();
      await wrapper
        .find('[data-testid="helpdesk-group-select"]')
        .setValue(groupKey);
      const label = wrapper.find('[data-testid="helpdesk-group-query-label"]');
      expect(label.element.control).toBe(label.find('input').element);
      await label
        .find('input')
        .setValue(' Reviewed knowledge or client history ');
      expect(mocks.api.groupPreview).not.toHaveBeenCalled();
      mocks.api.groupPreview.mockResolvedValueOnce({
        data: response(groupKey, 'R03'),
      });
      await wrapper
        .find('[data-testid="helpdesk-group-run-preview"]')
        .trigger('click');
      await flushPromises();
      expect(mocks.api.groupPreview).toHaveBeenCalledExactlyOnceWith(12, {
        event_id: 8,
        group_key: groupKey,
        input: { query: 'Reviewed knowledge or client history' },
      });
      wrapper.unmount();
    }
  );

  it('checks broker health only on an explicit request, clears action receipts and uses only the authorized native route', async () => {
    const { wrapper, router } = await page('R06');
    await wrapper.find('[data-testid="helpdesk-group-select"]').setValue('C2');
    await wrapper
      .find('[data-testid="helpdesk-group-binding-label"] input')
      .setValue('51');
    await wrapper
      .find('[data-testid="helpdesk-group-conversation-label"] input')
      .setValue('19');
    expect(mocks.api.groupPreview).not.toHaveBeenCalled();
    mocks.api.groupPreview.mockResolvedValueOnce({
      data: response('C2', 'R06'),
    });
    await wrapper
      .find('[data-testid="helpdesk-group-run-preview"]')
      .trigger('click');
    await flushPromises();
    expect(
      wrapper.find('[data-testid="helpdesk-group-prepare"]').exists()
    ).toBe(true);
    mocks.api.groupPreview.mockResolvedValueOnce({
      data: response('C2', 'R06', {
        broker: {
          binding_id: 51,
          conversation_id: 19,
          status: 'connected',
          pair_allowed: true,
          identity_approved: true,
          route_name: 'jrc_broker_connections',
        },
      }),
    });
    await wrapper
      .find('[data-testid="helpdesk-group-check-broker"]')
      .trigger('click');
    await flushPromises();
    expect(mocks.api.groupPreview).toHaveBeenLastCalledWith(12, {
      event_id: 8,
      group_key: 'C2',
      input: { binding_id: 51, conversation_id: 19, check_broker_status: true },
    });
    expect(
      wrapper.find('[data-testid="helpdesk-group-prepare"]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-testid="helpdesk-group-broker-health"]').text()
    ).toContain('connected');
    const link = wrapper.find('[data-testid="helpdesk-group-broker-route"]');
    expect(link.attributes('href')).toBe('/app/accounts/12/broker');
    expect(router.currentRoute.value.params.accountId).toBe('12');
    expect(mocks.api.groupPrepare).not.toHaveBeenCalled();
    mocks.api.groupPreview.mockResolvedValueOnce({
      data: response('C2', 'R06'),
    });
    await wrapper
      .find('[data-testid="helpdesk-group-run-preview"]')
      .trigger('click');
    await flushPromises();
    mocks.api.groupPrepare.mockResolvedValueOnce({ data: { id: 91 } });
    await wrapper
      .find('[data-testid="helpdesk-group-prepare"]')
      .trigger('click');
    await flushPromises();
    expect(mocks.api.groupPrepare).toHaveBeenCalledExactlyOnceWith(12, {
      event_id: 8,
      group_key: 'C2',
      input: { binding_id: 51, conversation_id: 19 },
      tool: 'add_service_ticket_note',
      arguments: { ticket_id: 21, body: 'Reviewed' },
      preview_digest: 'a'.repeat(64),
    });
    expect(
      wrapper.find('[data-testid="helpdesk-group-broker-health"]').exists()
    ).toBe(false);
    wrapper.unmount();
  });

  it('discards broker health on input or actor changes and rejects a mismatched binding response', async () => {
    const { wrapper } = await page('R06');
    await wrapper.find('[data-testid="helpdesk-group-select"]').setValue('C2');
    await wrapper
      .find('[data-testid="helpdesk-group-binding-label"] input')
      .setValue('51');
    await wrapper
      .find('[data-testid="helpdesk-group-conversation-label"] input')
      .setValue('19');
    mocks.api.groupPreview.mockResolvedValueOnce({
      data: response('C2', 'R06', {
        broker: {
          binding_id: 51,
          conversation_id: 19,
          status: 'offline',
          pair_allowed: false,
        },
      }),
    });
    await wrapper
      .find('[data-testid="helpdesk-group-check-broker"]')
      .trigger('click');
    await flushPromises();
    expect(
      wrapper.find('[data-testid="helpdesk-group-broker-route"]').exists()
    ).toBe(false);
    await wrapper
      .find('[data-testid="helpdesk-group-binding-label"] input')
      .setValue('52');
    expect(
      wrapper.find('[data-testid="helpdesk-group-broker-health"]').exists()
    ).toBe(false);
    await wrapper
      .find('[data-testid="helpdesk-group-binding-label"] input')
      .setValue('51');
    expect(
      wrapper.find('[data-testid="helpdesk-group-broker-health"]').exists()
    ).toBe(false);
    mocks.api.groupPreview.mockResolvedValueOnce({
      data: response('C2', 'R06', {
        broker: {
          binding_id: 52,
          conversation_id: 19,
          status: 'connected',
          pair_allowed: true,
          identity_approved: true,
          route_name: 'jrc_broker_connections',
        },
      }),
    });
    await wrapper
      .find('[data-testid="helpdesk-group-check-broker"]')
      .trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(
      wrapper.find('[data-testid="helpdesk-group-broker-route"]').exists()
    ).toBe(false);
    let finish;
    mocks.api.groupPreview.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    await wrapper
      .find('[data-testid="helpdesk-group-check-broker"]')
      .trigger('click');
    await wrapper.setProps({ contextKey: '12:8:agent' });
    expect(
      wrapper.find('[data-testid="helpdesk-group-check-broker"]').element
        .disabled
    ).toBe(false);
    finish({
      data: response('C2', 'R06', {
        broker: {
          binding_id: 51,
          conversation_id: 19,
          status: 'connected',
          pair_allowed: true,
          identity_approved: true,
          route_name: 'jrc_broker_connections',
        },
      }),
    });
    await flushPromises();
    expect(
      wrapper.find('[data-testid="helpdesk-group-broker-health"]').exists()
    ).toBe(false);
    expect(mocks.api.groupPrepare).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it.each([
    ['E', 'R03'],
    ['D2', 'R08'],
  ])(
    'prepares an explicit native activity in %s/%s without an invitation or immediate execution',
    async (groupKey, ruleKey) => {
      const { wrapper } = await page(ruleKey);
      await wrapper
        .find('[data-testid="helpdesk-group-select"]')
        .setValue(groupKey);
      expect(
        wrapper.find('[data-testid="helpdesk-group-activity"]').exists()
      ).toBe(true);
      await wrapper
        .find('[data-testid="helpdesk-group-activity-title"]')
        .setValue('Reviewed meeting');
      await wrapper
        .find('[data-testid="helpdesk-group-activity-due"]')
        .setValue('2026-10-09T14:00:00-03:00');
      await wrapper
        .find('[data-testid="helpdesk-group-activity-lead"]')
        .setValue('61');
      await wrapper
        .find('[data-testid="helpdesk-group-activity-description"]')
        .setValue('Current native client');
      const args = {
        lead_id: 61,
        title: 'Reviewed meeting',
        due_at: '2026-10-09T14:00:00-03:00',
        activity_type: ruleKey === 'R03' ? 'meeting' : 'follow_up',
      };
      mocks.api.groupPreview.mockResolvedValueOnce({
        data: response(groupKey, ruleKey, {
          actions: [
            { tool: 'create_activity', arguments: args, can_prepare: true },
          ],
        }),
      });
      await wrapper
        .find('[data-testid="helpdesk-group-run-preview"]')
        .trigger('click');
      await flushPromises();
      expect(mocks.api.groupPreview).toHaveBeenCalledExactlyOnceWith(12, {
        event_id: 8,
        group_key: groupKey,
        input: {
          activity: {
            title: 'Reviewed meeting',
            due_at: '2026-10-09T14:00:00-03:00',
            lead_id: 61,
            description: 'Current native client',
          },
        },
      });
      expect(mocks.api.groupPrepare).not.toHaveBeenCalled();
      mocks.api.groupPrepare.mockResolvedValueOnce({ data: { id: 91 } });
      await wrapper
        .find('[data-testid="helpdesk-group-prepare"]')
        .trigger('click');
      await flushPromises();
      expect(mocks.api.groupPrepare.mock.calls[0][1]).toMatchObject({
        tool: 'create_activity',
        arguments: args,
        preview_digest: 'a'.repeat(64),
      });
      wrapper.unmount();
    }
  );

  it('preserves the native messaging window block for an exact reviewed reply and clears inputs when changing group', async () => {
    const { wrapper } = await page('R10');
    await wrapper.find('[data-testid="helpdesk-group-select"]').setValue('D2');
    expect(wrapper.find('[data-testid="helpdesk-group-reply"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="helpdesk-group-activity"]').exists()
    ).toBe(false);
    await wrapper
      .find('[data-testid="helpdesk-group-reply-conversation"]')
      .setValue('19');
    await wrapper
      .find('[data-testid="helpdesk-group-reply-content"]')
      .setValue(' Exact reviewed response ');
    mocks.api.groupPreview.mockResolvedValueOnce({
      data: response('D2', 'R10', {
        executable: false,
        actions: [
          {
            tool: 'send_message',
            arguments: {
              conversation_id: 19,
              content: 'Exact reviewed response',
              private: false,
            },
            can_prepare: false,
            blocked_reason: 'native_messaging_window_closed',
          },
        ],
      }),
    });
    await wrapper
      .find('[data-testid="helpdesk-group-run-preview"]')
      .trigger('click');
    await flushPromises();
    expect(mocks.api.groupPreview).toHaveBeenCalledExactlyOnceWith(12, {
      event_id: 8,
      group_key: 'D2',
      input: {
        reply: { conversation_id: 19, content: 'Exact reviewed response' },
      },
    });
    expect(wrapper.text()).toContain('native_messaging_window_closed');
    expect(
      wrapper.find('[data-testid="helpdesk-group-prepare"]').element.disabled
    ).toBe(true);
    await wrapper
      .find('[data-testid="helpdesk-group-prepare"]')
      .trigger('click');
    expect(mocks.api.groupPrepare).not.toHaveBeenCalled();
    await wrapper.find('[data-testid="helpdesk-group-select"]').setValue('E');
    expect(wrapper.find('[data-testid="helpdesk-group-reply"]').exists()).toBe(
      false
    );
    await wrapper.find('[data-testid="helpdesk-group-select"]').setValue('D2');
    expect(
      wrapper.find('[data-testid="helpdesk-group-reply-content"]').element.value
    ).toBe('');
    expect(
      wrapper.find('[data-testid="helpdesk-group-reply-conversation"]').element
        .value
    ).toBe('');
    wrapper.unmount();
  });

  it('serializes only explicit native activity/reply fields and never carries a broker health flag into approval', () => {
    expect(
      helpdeskGroupInput({
        activity: {
          title: ' Reviewed ',
          due_at: '2026-10-09T14:00:00Z',
          deal_id: '72',
          description: ' Details ',
          invitation: true,
        },
        reply: {
          conversation_id: '19',
          content: ' Reviewed reply ',
          private: true,
        },
        check_broker_status: true,
      })
    ).toEqual({
      activity: {
        title: 'Reviewed',
        due_at: '2026-10-09T14:00:00Z',
        deal_id: 72,
        description: 'Details',
      },
      reply: { conversation_id: 19, content: 'Reviewed reply' },
    });
  });
});
