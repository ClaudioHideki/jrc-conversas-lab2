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
import Editor from '../NotificationPolicyEditor.vue';
const policy = {
  id: '90',
  event_type: 'customer_interaction',
  channel: 'email',
  enabled: false,
  template: '{{body}}',
  template_version: 'v1',
  inbox_id: null,
  version: 1,
  ticket_type_id: null,
  service_id: null,
};
const envelope = {
  contract_version: 1,
  account_id: '1',
  unit_id: '10',
  policies: [policy],
  event_types: ['customer_interaction'],
  inboxes: [
    { id: '7', name: 'Suporte', channel: 'email' },
    { id: '8', name: 'WhatsApp', channel: 'whatsapp' },
  ],
};
let wrapper;
const render = () => {
  wrapper = mount(Editor, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        Panel: { template: '<section><slot /></section>' },
        Button: {
          props: ['label', 'type', 'disabled'],
          template:
            '<button :type="type" :disabled="disabled">{{ label }}</button>',
        },
        ScopeBar: {
          emits: ['update:unitId'],
          template:
            "<button data-unit @click=\"$emit('update:unitId', '10')\">Unidade</button>",
        },
        LookupSelect: true,
        ServiceDefinitionSelect: true,
        State: true,
      },
    },
  });
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
        capabilities: { notifications: { manage: true } },
      },
    }),
  };
  holder.policies.mockResolvedValue(envelope);
});
afterEach(() => wrapper?.unmount());

describe('Notification policy editor', () => {
  it('offers only server-authorized inboxes for the selected channel', async () => {
    render();
    await wrapper.get('[data-unit]').trigger('click');
    await flushPromises();
    wrapper
      .findComponent({ name: 'ServiceDeskStepper' })
      .vm.$emit('update:modelValue', 'channels');
    await flushPromises();
    const selects = wrapper.findAll('select');
    expect(selects[1].text()).toContain('Suporte');
    expect(selects[1].text()).not.toContain('WhatsApp');
    await selects[0].setValue('whatsapp');
    expect(selects[1].text()).toContain('WhatsApp');
    expect(selects[1].text()).not.toContain('Suporte');
    expect(holder.publishPolicy).not.toHaveBeenCalled();
  });
  it('tests a model visibly with examples without publishing or sending', async () => {
    render();
    await wrapper.get('[data-unit]').trigger('click');
    await flushPromises();
    wrapper
      .findComponent({ name: 'ServiceDeskStepper' })
      .vm.$emit('update:modelValue', 'preview');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(
        button =>
          button.text() ===
          messages.JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.test_template
      )
      .trigger('click');
    expect(wrapper.findAll('pre')[0].text()).toBe(
      messages.JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.examples.body
    );
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.example_notice
    );
    expect(holder.publishPolicy).not.toHaveBeenCalled();
  });
  it('preserves confirmed feedback and enables editing after successful publication and readback', async () => {
    render();
    await wrapper.get('[data-unit]').trigger('click');
    await flushPromises();
    holder.publishPolicy.mockResolvedValue({ applied: true, account_id: '1' });
    holder.policies.mockResolvedValue({
      ...envelope,
      policies: [{ ...policy, id: '91', version: 2 }],
    });
    wrapper
      .findComponent({ name: 'ServiceDeskStepper' })
      .vm.$emit('update:modelValue', 'review');
    await flushPromises();
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper
      .findAll('button')
      .find(
        button => button.text() === messages.JRC_SERVICE_DESK.R2.save_policy
      )
      .trigger('click');
    await flushPromises();
    expect(holder.publishPolicy).toHaveBeenCalledOnce();
    expect(wrapper.text()).toContain(messages.JRC_SERVICE_DESK.R2.saved);
    wrapper
      .findComponent({ name: 'ServiceDeskStepper' })
      .vm.$emit('update:modelValue', 'message');
    await flushPromises();
    expect(wrapper.get('textarea').attributes('disabled')).toBeUndefined();
  });
  it('recovers the editor after a failed initial read and keeps publication gated', async () => {
    holder.policies.mockRejectedValueOnce(new Error('Unavailable'));
    render();
    await wrapper.get('[data-unit]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(messages.JRC_SERVICE_DESK.R2.unavailable);
    await wrapper
      .findAll('button')
      .find(button => button.text() === messages.JRC_SERVICE_DESK.COMMON.retry)
      .trigger('click');
    await flushPromises();
    expect(wrapper.findComponent({ name: 'ServiceDeskStepper' }).exists()).toBe(
      true
    );
    wrapper
      .findComponent({ name: 'ServiceDeskStepper' })
      .vm.$emit('update:modelValue', 'review');
    await flushPromises();
    expect(
      wrapper
        .findAll('button')
        .find(
          button => button.text() === messages.JRC_SERVICE_DESK.R2.save_policy
        ).element.disabled
    ).toBe(true);
    expect(wrapper.text()).not.toContain(
      messages.JRC_SERVICE_DESK.R2.unavailable
    );
    expect(holder.publishPolicy).not.toHaveBeenCalled();
  });
});
