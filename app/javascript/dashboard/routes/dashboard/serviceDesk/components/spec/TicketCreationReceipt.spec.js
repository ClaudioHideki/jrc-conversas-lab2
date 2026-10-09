import { afterEach, describe, expect, it, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import TicketCreationReceipt from '../TicketCreationReceipt.vue';
import TicketProtocol from '../TicketProtocol.vue';

const mocks = vi.hoisted(() => ({ copy: vi.fn() }));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: mocks.copy,
}));
const Button = {
  props: ['label', 'disabled'],
  template: '<button :disabled="disabled">{{ label }}</button>',
};
const row = overrides => ({
  id: '249',
  number: '249',
  title: 'Synthetic protocol test',
  status: { id: '1', name: 'New' },
  queue: { id: '6', name: 'Support' },
  team: null,
  assignee: { id: '77', name: 'Selected agent' },
  ...overrides,
});
let wrapper;
afterEach(() => {
  wrapper?.unmount();
  vi.clearAllMocks();
});
const render = (component, ticket = row()) => {
  wrapper = mount(component, {
    props: { ticket },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
      stubs: { Button, Icon: true },
    },
  });
  return wrapper;
};

describe('Ticket protocol receipt UI', () => {
  it('shows the confirmed protocol, persisted agent and queue', () => {
    render(TicketCreationReceipt);
    expect(wrapper.find('[data-testid="ticket-protocol"]').text()).toContain(
      '249'
    );
    expect(wrapper.text()).toContain('Selected agent');
    expect(wrapper.text()).toContain('Support');
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.CREATION.verified
    );
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.CREATION.delivery_help
    );
  });

  it('shows an explicit unassigned outcome instead of pretending the ticket reached an agent', () => {
    render(TicketCreationReceipt, row({ assignee: null }));
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.CREATION.unassigned
    );
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.CREATION.assignment_pending
    );
  });

  it('copies the authoritative number, not the title or a fabricated prefix', async () => {
    mocks.copy.mockResolvedValue();
    render(TicketProtocol);
    await wrapper.find('[data-testid="copy-ticket-protocol"]').trigger('click');
    await flushPromises();
    expect(mocks.copy).toHaveBeenCalledTimes(1);
    expect(mocks.copy).toHaveBeenCalledWith('249');
    expect(wrapper.text()).toContain(messages.JRC_SERVICE_DESK.CREATION.copied);
  });

  it('keeps the number selectable and reports a clipboard error without claiming success', async () => {
    mocks.copy.mockRejectedValue(new Error('clipboard denied'));
    render(TicketProtocol);
    await wrapper.find('[data-testid="copy-ticket-protocol"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('strong').text()).toBe('249');
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.CREATION.copy_failed
    );
    expect(wrapper.text()).not.toContain(
      messages.JRC_SERVICE_DESK.CREATION.copied
    );
  });

  it('navigates using the real ticket id even when the presented number has a label', async () => {
    render(TicketCreationReceipt, row({ number: 'SERVER-249' }));
    await wrapper.find('[data-testid="open-created-ticket"]').trigger('click');
    expect(wrapper.emitted('open')).toEqual([['249']]);
  });

  it('does not display a protocol for an unpersisted ticket', () => {
    render(TicketProtocol, { title: 'Draft', number: 'invented' });
    expect(wrapper.find('[data-testid="ticket-protocol"]').exists()).toBe(
      false
    );
  });
});
