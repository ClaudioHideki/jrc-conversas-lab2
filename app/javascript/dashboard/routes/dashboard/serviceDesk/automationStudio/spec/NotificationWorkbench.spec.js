import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
const holder = vi.hoisted(() => ({
  session: null,
  policies: vi.fn(),
  publishPolicy: vi.fn(),
}));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => holder.session,
}));
vi.mock('dashboard/api/serviceDeskCockpit', () => ({ default: holder }));
vi.mock('dashboard/api/serviceDeskAutomationInsights', () => ({
  default: {
    read: vi.fn(async () => ({
      active_policies: 0,
      confirmed_sent: 0,
      delivery_rate: null,
      notified_requesters: 0,
    })),
  },
}));
import Workbench from '../NotificationWorkbench.vue';
const settings = () => ({
  conditions: { operator: 'all', items: [] },
  channel_order: ['email', 'whatsapp'],
  multichannel_mode: 'first_available',
  additional_contact_ids: [],
  internal_copy_member_ids: [],
  window: { enabled: false },
  outside_window: 'defer',
  max_attempts: 1,
  backoff_minutes: 10,
});
const policy = channel => ({
  id: channel === 'email' ? '90' : '91',
  channel,
  event_type: 'ticket_created',
  enabled: true,
  template: `${channel} {{number}}`,
  template_version: 'v1',
  inbox_id: channel === 'email' ? '7' : '8',
  version: 1,
  ticket_type_id: null,
  service_id: null,
  display_name: 'Synthetic policy',
  description: 'Synthetic description',
  settings: settings(),
});
const envelope = rows => ({
  contract_version: 1,
  account_id: '1',
  unit_id: '10',
  event_types: ['ticket_created'],
  policies: rows,
  inboxes: [
    { id: '7', name: 'Synthetic email', channel: 'email' },
    { id: '8', name: 'Synthetic Broker WhatsApp', channel: 'whatsapp' },
  ],
});
let wrapper;
const render = async () => {
  wrapper = mount(Workbench, {
    props: { initialUnitId: '10' },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        ScopeBar: true,
        LookupSelect: true,
        ServiceDefinitionSelect: true,
        AutomationDialog: {
          props: ['open'],
          template:
            '<section v-if="open"><slot /><slot name="footer" /></section>',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};
beforeEach(() => {
  vi.clearAllMocks();
  holder.session = {
    state: reactive({
      status: 'ready',
      context: {
        account_id: '1',
        user_id: '2',
        units: [{ id: '10', name: 'Synthetic unit' }],
        capabilities: { notifications: { manage: true } },
      },
    }),
  };
  holder.policies.mockResolvedValue(
    envelope([policy('email'), policy('whatsapp')])
  );
});
afterEach(() => wrapper?.unmount());
describe('Native multichannel notification workbench', () => {
  it('does not load or expose policy controls without the affirmative backend grant', async () => {
    holder.session.state.context.capabilities.notifications.manage = false;
    await render();
    expect(wrapper.text()).toBe('');
    expect(holder.policies).not.toHaveBeenCalled();
    expect(holder.publishPolicy).not.toHaveBeenCalled();
  });
  it('reopens both native channel configurations and requires the selected sender for each enabled channel', async () => {
    await render();
    await wrapper.vm.edit(policy('email'));
    await flushPromises();
    expect(wrapper.vm.channelConfigurations.whatsapp.inbox_id).toBe('8');
    expect(wrapper.vm.validConfigurations).toBe(true);
    wrapper.vm.channelConfigurations.whatsapp.inbox_id = '7';
    await flushPromises();
    expect(wrapper.vm.canPublish).toBe(false);
    wrapper.vm.confirmed = true;
    await wrapper.vm.publishFinal();
    expect(holder.publishPolicy).not.toHaveBeenCalled();
  });
  it('verifies the persisted settings and every channel after atomic publication, without sending messages', async () => {
    await render();
    await wrapper.vm.edit(policy('email'));
    await flushPromises();
    holder.publishPolicy.mockImplementation(
      async (_account, _unit, submitted) => {
        holder.policies.mockResolvedValue(
          envelope(
            submitted.settings.channel_order.map(channel => ({
              ...policy(channel),
              version: 2,
              ...submitted.channel_configurations[channel],
              settings: submitted.settings,
            }))
          )
        );
        return { applied: true, account_id: '1' };
      }
    );
    wrapper.vm.confirmed = true;
    await wrapper.vm.publishFinal();
    await flushPromises();
    expect(holder.publishPolicy).toHaveBeenCalledOnce();
    expect(wrapper.vm.feedback).toBe('saved');
    expect(wrapper.vm.locked).toBe(false);
    const sent = holder.publishPolicy.mock.calls[0][2];
    expect(sent.expected_versions).toEqual({ email: 1, whatsapp: 1 });
    expect(sent.channel_configurations.whatsapp.inbox_id).toBe('8');
  });
  it('does not report success when the independent readback changes a sibling configuration', async () => {
    await render();
    await wrapper.vm.edit(policy('email'));
    await flushPromises();
    holder.publishPolicy.mockImplementation(async () => {
      holder.policies.mockResolvedValue(
        envelope([
          { ...policy('email'), version: 2 },
          {
            ...policy('whatsapp'),
            version: 2,
            template: 'Different persisted message',
          },
        ])
      );
      return { applied: true, account_id: '1' };
    });
    wrapper.vm.confirmed = true;
    await wrapper.vm.publishFinal();
    await flushPromises();
    expect(wrapper.vm.feedback).toBe('uncertain');
    expect(wrapper.vm.publicationUncertain).toBe(true);
    await wrapper.vm.publishFinal();
    expect(holder.publishPolicy).toHaveBeenCalledOnce();
  });
  it('recovers a lost publication response through readback and never repeats the publication automatically', async () => {
    await render();
    await wrapper.vm.edit(policy('email'));
    await flushPromises();
    holder.publishPolicy.mockImplementation(async () => {
      holder.policies.mockResolvedValue(
        envelope([
          { ...policy('email'), version: 2 },
          { ...policy('whatsapp'), version: 2 },
        ])
      );
      throw new Error('Synthetic response lost after commit');
    });
    wrapper.vm.confirmed = true;
    await wrapper.vm.publishFinal();
    expect(wrapper.vm.publicationUncertain).toBe(true);
    await wrapper.vm.load();
    await flushPromises();
    expect(wrapper.vm.feedback).toBe('saved');
    expect(wrapper.vm.publicationUncertain).toBe(false);
    expect(holder.publishPolicy).toHaveBeenCalledOnce();
  });
  it('copies into a disabled draft and closes protected controls after permission revocation', async () => {
    await render();
    await wrapper.vm.copyDraft(policy('email'));
    await flushPromises();
    expect(wrapper.vm.enabled).toBe(false);
    expect(holder.publishPolicy).not.toHaveBeenCalled();
    holder.session.state.context.capabilities.notifications.manage = false;
    await flushPromises();
    expect(wrapper.text()).toBe('');
  });
});
