import { beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import InteractionComposer from '../InteractionComposer.vue';

const mocks = vi.hoisted(() => ({
  session: null,
  composer: vi.fn(),
  preview: vi.fn(),
  interaction: vi.fn(),
  read: vi.fn(),
}));
vi.mock('dashboard/api/serviceDeskCockpit', () => ({ default: mocks }));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
const ticket = {
  id: '3',
  account_id: '1',
  unit_id: '2',
  lock_version: 0,
  team: { id: '7' },
};
const choices = () => ({
  contract_version: 1,
  account_id: '1',
  composer: {
    account_id: '1',
    unit_id: '2',
    ticket_id: '3',
    audiences: [
      'internal',
      'technical_team',
      'customer',
      'public_without_notification',
    ],
    recipient: { id: '6', name: 'Verified customer' },
    channels: [
      {
        channel: 'email',
        available: true,
        destinations: [
          {
            conversation_id: '8',
            recipient: 'customer@example.test',
            available: true,
            reason: null,
          },
        ],
      },
      {
        channel: 'whatsapp',
        available: false,
        reason: 'no_authorized_conversation',
        destinations: [],
      },
    ],
  },
});
const approved = () => ({
  contract_version: 1,
  account_id: '1',
  preview: {
    account_id: '1',
    unit_id: '2',
    ticket_id: '3',
    body: 'Reviewed content',
    audience: 'internal',
    receipt: 'opaque-reviewed-receipt',
    expires_at: new Date(Date.now() + 300000).toISOString(),
    can_publish: true,
    deliveries: [],
  },
});
const readback = () => ({
  contract_version: 1,
  account_id: '1',
  ticket: { id: '3', unit_id: '2' },
  cockpit: {
    notes: [
      {
        id: '9',
        account_id: '1',
        unit_id: '2',
        ticket_id: '3',
        permissions: { show: true },
        body: 'Reviewed content',
        visibility: 'internal',
        author: null,
        attachments: [],
        deliveries: [],
      },
    ],
    tasks: [],
    approvals: [],
    events: [],
    conversations: [],
    approvers: [],
    incident: null,
  },
});

beforeEach(() => {
  vi.clearAllMocks();
  mocks.session = reactive({
    state: {
      status: 'ready',
      context: { account_id: '1', units: [{ id: '2' }] },
    },
  });
  mocks.composer.mockResolvedValue(choices());
  mocks.preview.mockResolvedValue(approved());
  mocks.interaction.mockResolvedValue({
    contract_version: 1,
    account_id: '1',
    ticket_id: '3',
    operation: 'add_interaction',
    result_id: '9',
    applied: true,
  });
  mocks.read.mockResolvedValue(readback());
});

describe('reviewed four audience composer', () => {
  it('requires a preview then independent GET before confirming a write', async () => {
    const wrapper = mount(InteractionComposer, { props: { ticket } });
    await flushPromises();
    await wrapper.get('textarea').setValue('Reviewed content');
    expect(wrapper.find('button[type="submit"]').exists()).toBe(false);
    await wrapper.get('button[type="button"]').trigger('click');
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.interaction.mock.calls[0][6]).toBe('opaque-reviewed-receipt');
    expect(mocks.read).toHaveBeenCalledOnce();
    expect(wrapper.emitted('updated')).toEqual([
      [
        {
          operation: 'add_interaction',
          account_id: '1',
          unit_id: '2',
          ticket_id: '3',
          result_id: '9',
          outcome: 'saved',
        },
      ],
    ]);
    wrapper.unmount();
  });
  it('invalidates the previous preview when its literal content or audience changes', async () => {
    const wrapper = mount(InteractionComposer, { props: { ticket } });
    await flushPromises();
    await wrapper.get('textarea').setValue('Reviewed content');
    await wrapper.get('button[type="button"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('button[type="submit"]').exists()).toBe(true);
    await wrapper.get('textarea').setValue('Changed content');
    expect(wrapper.find('button[type="submit"]').exists()).toBe(false);
    expect(mocks.interaction).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('shows literal recipients and unavailable native channels without allowing their selection', async () => {
    const wrapper = mount(InteractionComposer, { props: { ticket } });
    await flushPromises();
    await wrapper.get('select').setValue('customer');
    const inputs = wrapper.findAll('input[type="checkbox"]');
    expect(inputs[0].attributes('disabled')).toBeUndefined();
    expect(inputs[1].attributes('disabled')).toBeDefined();
    await inputs[0].setValue(true);
    expect(wrapper.text()).toContain('customer@example.test');
    expect(wrapper.text()).toContain('Verified customer');
    wrapper.unmount();
  });
  it('clears private draft and recipients immediately after account grant revocation', async () => {
    const wrapper = mount(InteractionComposer, { props: { ticket } });
    await flushPromises();
    await wrapper.get('textarea').setValue('Private draft');
    mocks.session.state.context = null;
    mocks.session.state.status = 'denied';
    await flushPromises();
    expect(wrapper.find('textarea').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('Private draft');
    wrapper.unmount();
  });
  it('keeps one request key after uncertain readback and confirms only persisted matching content', async () => {
    mocks.read.mockRejectedValueOnce(new Error('Readback unavailable'));
    const wrapper = mount(InteractionComposer, { props: { ticket } });
    await flushPromises();
    await wrapper.get('textarea').setValue('Reviewed content');
    await wrapper.get('button[type="button"]').trigger('click');
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.emitted('updated')).toBeUndefined();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.interaction.mock.calls[0][4]).toBe(
      mocks.interaction.mock.calls[1][4]
    );
    expect(wrapper.emitted('updated')).toHaveLength(1);
    wrapper.unmount();
  });
});
