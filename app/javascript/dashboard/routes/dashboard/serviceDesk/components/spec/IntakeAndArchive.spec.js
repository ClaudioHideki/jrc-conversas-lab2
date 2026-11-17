import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import InternalTicketForm from '../InternalTicketForm.vue';
import ArchivedTicketsDialog from '../ArchivedTicketsDialog.vue';

let session;
let wrapper;
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => session,
}));
const unit = (id, company, primary) => ({
  id,
  name: `Unit ${id}`,
  operator_company: { id: company, name: `Company ${company}` },
  permissions: { create_ticket: true },
  internal_intake: {
    requester: { name: 'Synthetic employee', email: 'employee@example.test' },
    primary: { id: primary, name: `Agent ${primary}` },
    assignees: [
      { id: primary, name: `Agent ${primary}` },
      { id: `${primary}1`, name: 'Another eligible agent' },
    ],
  },
});
const render = component => {
  wrapper = mount(component, {
    props:
      component === ArchivedTicketsDialog
        ? { query: { phase: 'archived', unit_id: '10' } }
        : {},
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        ServiceDefinitionSelect: true,
        CatalogueAnswers: true,
        WriteFeedback: true,
        TicketCreationReceipt: true,
        TicketTable: {
          props: ['items'],
          template:
            '<div data-testid="archive-records">{{ items.length }}</div>',
        },
        PaginationFooter: {
          name: 'PaginationFooter',
          template:
            '<button @click="$emit(\'update:currentPage\', 2)">Next page</button>',
        },
      },
    },
  });
};

beforeEach(() => {
  HTMLDialogElement.prototype.showModal = vi.fn();
  session = {
    accountId: ref('1'),
    userId: ref('2'),
    state: reactive({
      status: 'ready',
      context: {
        account_id: '1',
        user_id: '2',
        units: [unit('10', '3', '7'), unit('20', '4', '8')],
      },
    }),
    operations: {
      state: reactive({ revision: 0 }),
      mutation: () => ({ status: 'idle' }),
      dismissConfirmation: vi.fn(),
      cancel: vi.fn(),
      write: vi.fn().mockResolvedValue(null),
    },
    resource: () => ({
      status: 'ready',
      items: [{ id: '100' }],
      meta: { page: 1, per_page: 20, total: 21 },
    }),
    load: vi.fn(),
    resetResource: vi.fn(),
  };
});
afterEach(() => wrapper?.unmount());

describe('Employee recipient and closed-ticket journeys', () => {
  it('clears the recipient when switching companies and submits the selected person', async () => {
    render(InternalTicketForm);
    await wrapper.findAll('select')[0].setValue('3');
    await flushPromises();
    expect(wrapper.findAll('select')[1].element.value).toBe('7');
    await wrapper.findAll('select')[1].setValue('71');
    await wrapper.findAll('select')[0].setValue('4');
    await flushPromises();
    expect(wrapper.findAll('select')[1].element.value).toBe('8');
    expect(wrapper.text()).not.toContain('Agent 7');
    await wrapper.findAll('select')[1].setValue('81');
    await wrapper.get('input[maxlength="255"]').setValue('Synthetic request');
    await wrapper.get('textarea').setValue('Synthetic description');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(session.operations.write).toHaveBeenCalledWith(
      'ticket:internal:write',
      'create',
      expect.objectContaining({
        unit_id: '20',
        internal_request: true,
        ticket: expect.objectContaining({ assignee_account_user_id: '81' }),
      })
    );
  });

  it('opens a paginated archive using its separate query and closes with Escape', async () => {
    render(ArchivedTicketsDialog);
    await flushPromises();
    expect(HTMLDialogElement.prototype.showModal).toHaveBeenCalledOnce();
    expect(session.load).toHaveBeenCalledWith(
      'tickets:archived',
      'tickets',
      { phase: 'archived', unit_id: '10' },
      null,
      { background: false }
    );
    expect(wrapper.get('[data-testid="archive-records"]').text()).toBe('1');
    await wrapper.getComponent({ name: 'PaginationFooter' }).trigger('click');
    expect(wrapper.emitted('page')).toEqual([[2]]);
    await wrapper.get('dialog').trigger('cancel');
    expect(wrapper.emitted('close')).toHaveLength(1);
    wrapper.unmount();
    expect(session.resetResource).toHaveBeenCalledWith('tickets:archived');
    wrapper = null;
  });
});
