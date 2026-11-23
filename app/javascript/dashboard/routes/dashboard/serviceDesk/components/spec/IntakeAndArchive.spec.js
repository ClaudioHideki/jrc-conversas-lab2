import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import InternalTicketForm from '../InternalTicketForm.vue';
import ArchivedTicketsDialog from '../ArchivedTicketsDialog.vue';
import {
  createOperationalSession,
  createOperationalState,
} from '../../helpers/operationalSession';
import { createServiceDeskOperationsClient } from 'dashboard/api/serviceDeskOperationsClient';

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
  it('preserves the mounted draft and refuses the operation locally on a real client POST 403', async () => {
    session.state.context.available = true;
    session.state.context.units = [unit('10', '3', '7')];
    session.dispose = vi.fn(() => {
      session.state.context = null;
    });
    const http = {
      post: vi.fn().mockRejectedValue({
        response: { status: 403, data: { code: 'forbidden' } },
      }),
    };
    session.operations = createOperationalSession(
      createServiceDeskOperationsClient(http),
      session,
      reactive(createOperationalState())
    );
    render(InternalTicketForm);
    wrapper
      .getComponent({ name: 'ServiceDefinitionSelect' })
      .vm.$emit('update:modelValue', '35');
    await flushPromises();
    wrapper.getComponent({ name: 'CatalogueAnswers' }).vm.$emit('ready', true);
    await wrapper.get('input[maxlength="255"]').setValue('Synthetic request');
    await wrapper.get('textarea').setValue('Synthetic description');
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(http.post).toHaveBeenCalledOnce();
    expect(http.post.mock.calls[0][1]).toEqual({
      unit_id: '10',
      internal_request: true,
      service_id: '35',
      ticket: {
        title: 'Synthetic request',
        description: 'Synthetic description',
        service_fields: {},
        assignee_account_user_id: '7',
      },
    });
    expect(session.dispose).not.toHaveBeenCalled();
    expect(session.state.status).toBe('ready');
    expect(wrapper.get('input[maxlength="255"]').element.value).toBe(
      'Synthetic request'
    );
    expect(wrapper.get('textarea').element.value).toBe('Synthetic description');
    expect(
      wrapper.getComponent({ name: 'WriteFeedback' }).props('status')
    ).toBe('forbidden');
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.LIFECYCLE.feedback.denied
    );
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(http.post.mock.calls[1][1]).toEqual(http.post.mock.calls[0][1]);
    expect(http.post.mock.calls[1][2].headers).toEqual(
      http.post.mock.calls[0][2].headers
    );
    session.operations.clear();
  });

  it('requires a chosen recipient when legacy triage has no default', async () => {
    const destination = unit('10', '3', '7');
    destination.internal_intake.primary = null;
    session.state.context.units = [destination];
    render(InternalTicketForm);
    await flushPromises();
    expect(wrapper.findAll('select')[1].element.value).toBe('');
    await wrapper.findAll('select')[1].setValue('71');
    await wrapper.get('input[maxlength="255"]').setValue('Synthetic request');
    await wrapper.get('textarea').setValue('Synthetic description');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(session.operations.write).toHaveBeenCalledWith(
      'ticket:internal:write',
      'create',
      expect.objectContaining({
        unit_id: '10',
        ticket: expect.objectContaining({ assignee_account_user_id: '71' }),
      })
    );
  });

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
