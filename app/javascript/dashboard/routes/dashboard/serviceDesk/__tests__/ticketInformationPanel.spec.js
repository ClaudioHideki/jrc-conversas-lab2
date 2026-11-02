import { describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import TicketInformationPanel from '../components/TicketInformationPanel.vue';
import { ticket } from './fixtures';

vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => ({
    state: { context: { units: [{ id: '10', name: 'Unidade de teste' }] } },
  }),
}));
const render = (record = ticket(), activeTab = 'conversation') =>
  mount(TicketInformationPanel, {
    props: { ticket: record, activeTab },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        TicketTimeline: {
          props: ['view'],
          template: '<div :data-timeline="view" />',
        },
        Button: { props: ['label'], template: '<button>{{ label }}</button>' },
      },
    },
  });

describe('authorized ticket information panel', () => {
  it('shows the real requester and classification without inventing an assignee', async () => {
    const wrapper = render(
      ticket({
        assignee: null,
        permissions: { ...ticket().permissions, assign: true },
        service: { id: '4', name: 'Correio corporativo' },
        requester: {
          id: '33',
          name: 'Pessoa de teste',
          email: 'person@example.invalid',
          phone_number: '+5511999990001',
        },
      })
    );
    expect(wrapper.text()).toContain('Correio corporativo');
    expect(wrapper.text()).toContain('person@example.invalid');
    expect(wrapper.text()).toContain('+5511999990001');
    const assign = wrapper
      .findAll('button')
      .find(button => button.text() === 'Atribuir');
    expect(assign).toBeTruthy();
    await assign.trigger('click');
    expect(wrapper.emitted('assign')).toHaveLength(1);
    wrapper.unmount();
  });

  it('does not mount notes/files or history readers when these actions are denied', () => {
    const wrapper = render(
      ticket({
        permissions: {
          ...ticket().permissions,
          update: false,
          assign: false,
          view_notes: false,
          view_history: false,
        },
      })
    );
    expect(wrapper.find('[data-timeline]').exists()).toBe(false);
    expect(wrapper.findAll('button')).toHaveLength(0);
    wrapper.unmount();
  });

  it('shows files in exactly one location while the files tab is active', () => {
    const wrapper = render(ticket(), 'files');
    expect(wrapper.find('[data-timeline="files"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Arquivos exibidos na aba ao lado');
    wrapper.unmount();
  });

  it('navigates to the full real history instead of reconstructing status events', async () => {
    const wrapper = render();
    expect(wrapper.find('[data-timeline="history"]').exists()).toBe(true);
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Ver histórico completo')
      .trigger('click');
    expect(wrapper.emitted('tab')).toEqual([['history']]);
    await wrapper.setProps({ activeTab: 'history' });
    expect(wrapper.find('[data-timeline="history"]').exists()).toBe(false);
    wrapper.unmount();
  });
});
