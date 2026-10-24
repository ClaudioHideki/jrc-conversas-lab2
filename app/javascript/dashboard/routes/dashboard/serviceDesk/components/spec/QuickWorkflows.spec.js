import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import {
  lcContext,
  lcPayload,
  lcTicket,
  lcTransition,
} from '../../__tests__/lifecycleCases';
import { detail, ticket } from '../../__tests__/fixtures';
import { normalizeQuery } from '../../helpers/query';
import { decodeLifecycle } from '../../helpers/lifecycle';
import { ticketTypePreferenceKey } from '../../helpers/quickIntake';
import { createServiceDeskClient } from 'dashboard/api/serviceDeskClient';

const mocks = vi.hoisted(() => ({
  session: null,
  read: vi.fn(),
  apply: vi.fn(),
  transition: vi.fn(),
  ticket: vi.fn(),
  saveContact: vi.fn(),
}));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
vi.mock('dashboard/api/serviceDeskLifecycle', () => ({ default: mocks }));
vi.mock('dashboard/api/jrcCustomers', () => ({
  default: { saveContact: (...args) => mocks.saveContact(...args) },
}));
vi.mock('dashboard/routes/dashboard/jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ canAccess: ref(true) }),
}));
import CloseTicketForm from '../CloseTicketForm.vue';
import QuickTicketForm from '../QuickTicketForm.vue';
import NativeLookupSelect from '../LookupSelect.vue';

const Button = {
  props: ['label', 'disabled', 'type'],
  template:
    '<button :type="type || \'button\'" :disabled="disabled">{{ label }}</button>',
};
const Input = {
  props: ['modelValue', 'label', 'disabled'],
  emits: ['update:modelValue'],
  template:
    '<label>{{ label }}<input :value="modelValue" :disabled="disabled" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>',
};
const TextArea = {
  props: ['modelValue', 'label', 'disabled'],
  emits: ['update:modelValue'],
  template:
    '<label>{{ label }}<textarea :value="modelValue" :disabled="disabled" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>',
};
const LookupSelect = {
  props: ['modelValue', 'label', 'resource', 'companyId', 'disabled'],
  emits: ['update:modelValue', 'selected'],
  template:
    '<label>{{ label }}<select :data-resource="resource" :value="modelValue" :disabled="disabled" @change="$emit(\'update:modelValue\', $event.target.value)"><option value=""/><option value="33">Synthetic person</option><option value="5">Normal</option><option value="6">Synthetic type</option></select></label>',
};
const globals = () => ({
  plugins: [
    createI18n({
      legacy: false,
      locale: 'pt_BR',
      messages: { pt_BR: messages },
    }),
  ],
  stubs: {
    Button,
    Input,
    TextArea,
    Select: true,
    State: { props: ['status'], template: '<p :data-state="status" />' },
    LookupSelect,
    ScopeBar: true,
    CompanyPicker: {
      name: 'CompanyPicker',
      props: ['modelValue'],
      emits: ['update:modelValue'],
      template:
        '<button type="button" data-company @click="$emit(\'update:modelValue\', 80)">Synthetic company</button>',
    },
    TicketCreationReceipt: {
      name: 'TicketCreationReceipt',
      props: ['ticket'],
      template: '<p data-receipt>{{ ticket.id }}</p>',
    },
    CatalogueAnswers: true,
    WriteFeedback: true,
  },
});
const requirements = () => ({
  note: false,
  solution: false,
  evidence: false,
  classification: false,
  fields: {
    closing_reason: {
      label: 'Motivo do encerramento',
      type: 'text',
      required: true,
    },
  },
});
const resolve = () => ({
  key: 'resolve',
  action: 'resolve',
  to_status_id: '2',
  to_status_name: 'Resolvido',
  requirements: requirements(),
  reasons: [],
});
const close = () => ({
  key: 'close',
  action: 'close',
  to_status_id: '3',
  to_status_name: 'Encerrado',
  requirements: requirements(),
  reasons: [],
});
let wrapper;
beforeEach(() => {
  vi.stubGlobal('crypto', { randomUUID: () => 'synthetic-intent' });
  localStorage.clear();
  mocks.session = {
    state: reactive({ status: 'ready', context: lcContext() }),
    operations: { state: reactive({ revision: 0 }) },
  };
});
afterEach(() => {
  wrapper?.unmount();
  vi.resetAllMocks();
  vi.unstubAllGlobals();
});

function closureTransport({ failClose = null, extra = null } = {}) {
  let phase = 0;
  let failure = failClose;
  const committed = new Map();
  const r = resolve();
  const c = close();
  if (extra) c.requirements = extra;
  mocks.read.mockImplementation(async () => {
    const options = [[r], [c], []][phase];
    return lcPayload({
      lock_version: phase,
      options,
      closure_options:
        phase < 2
          ? [
              {
                key: phase === 0 ? 'resolve:close' : 'close',
                steps: phase === 0 ? [r, c] : [c],
              },
            ]
          : [],
    });
  });
  mocks.apply.mockImplementation(async (_a, _t, command, key) => {
    if (!committed.has(key)) {
      phase += 1;
      committed.set(key, { command, id: String(80 + phase), phase });
    }
    if (command.rule_key === 'close' && failure) {
      const error = failure;
      failure = null;
      throw error;
    }
    return {
      contract_version: 1,
      account_id: '1',
      applied: true,
      operation: 'lifecycle',
      ticket_id: '20',
      result_id: committed.get(key).id,
    };
  });
  mocks.transition.mockImplementation(async (_a, _t, id) => {
    const [key, row] = [...committed.entries()].find(([, v]) => v.id === id);
    return {
      contract_version: 1,
      account_id: '1',
      transition: lcTransition({
        id,
        action: row.command.rule_key,
        rule_key: row.command.rule_key,
        request_key: key,
        to_status_id: String(row.phase + 1),
        payload: { ...row.command, sla: { cycle_id: null } },
      }),
    };
  });
  mocks.ticket.mockImplementation(async () =>
    detail(
      ticket({
        lock_version: phase,
        status: {
          id: String(phase + 1),
          name: phase === 2 ? 'Encerrado' : 'Resolvido',
        },
      })
    )
  );
  return committed;
}
async function renderClosure() {
  wrapper = mount(CloseTicketForm, {
    props: { ticket: lcTicket() },
    global: globals(),
  });
  await flushPromises();
}

describe('one-confirmation official closure', () => {
  it('unlocks cancellation and requests a fresh parent read when authorization is lost after the POST acknowledgement', async () => {
    closureTransport();
    mocks.ticket.mockRejectedValueOnce({ response: { status: 403 } });
    await renderClosure();
    await wrapper.get('textarea').setValue('Resolução protegida');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(wrapper.emitted('refresh')).toHaveLength(1);
    expect(wrapper.emitted('busyChange').at(-1)).toEqual([false]);
    expect(wrapper.find('textarea').exists()).toBe(false);
    await wrapper.get('button').trigger('click');
    expect(wrapper.emitted('cancel')).toHaveLength(1);
    expect(mocks.apply).toHaveBeenCalledTimes(1);
  });
  it('explains a mandatory pending approval without offering a close command', async () => {
    mocks.read.mockResolvedValue(
      lcPayload({
        closure_options: [],
        closure_unavailable_reason: 'service_approval_required',
      })
    );
    await renderClosure();
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.QUICK.service_approval_required
    );
    expect(wrapper.find('form').exists()).toBe(false);
    expect(mocks.apply).not.toHaveBeenCalled();
  });
  it('ignores a double click while the official request is in flight', async () => {
    const committed = closureTransport();
    const original = mocks.apply.getMockImplementation();
    let release;
    const gate = new Promise(resolveGate => {
      release = resolveGate;
    });
    mocks.apply.mockImplementationOnce(async (...args) => {
      await gate;
      return original(...args);
    });
    await renderClosure();
    await wrapper.get('textarea').setValue('Resolução sintética');
    await wrapper.get('form').trigger('submit');
    await wrapper.get('form').trigger('submit');
    expect(mocks.apply).toHaveBeenCalledTimes(1);
    release();
    await flushPromises();
    expect(committed.size).toBe(2);
    expect(wrapper.emitted('updated')).toHaveLength(1);
  });
  it('shows only the reason and executes both transitions with verified independent readbacks', async () => {
    const committed = closureTransport();
    await renderClosure();
    expect(wrapper.findAll('textarea')).toHaveLength(1);
    expect(wrapper.find('input[type="checkbox"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('Política versão');
    await wrapper.get('textarea').setValue('Resolução sintética');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.apply.mock.calls.map(row => row[2].rule_key)).toEqual([
      'resolve',
      'close',
    ]);
    expect(committed.size).toBe(2);
    expect(
      mocks.apply.mock.calls.every(
        row => row[2].closing_reason === 'Resolução sintética'
      )
    ).toBe(true);
    expect(
      mocks.apply.mock.calls.every(
        row =>
          !Object.hasOwn(row[2], 'solution') && !Object.hasOwn(row[2], 'note')
      )
    ).toBe(true);
    expect(mocks.transition).toHaveBeenCalledTimes(2);
    expect(mocks.ticket).toHaveBeenCalledTimes(2);
    expect(wrapper.emitted('updated')[0][0].status.id).toBe('3');
  });

  it('does not execute commands with a blank reason or without a complete authorized plan', async () => {
    closureTransport();
    await renderClosure();
    await wrapper.get('form').trigger('submit');
    expect(mocks.apply).not.toHaveBeenCalled();
    wrapper.unmount();
    mocks.read.mockResolvedValue(lcPayload({ closure_options: [] }));
    await renderClosure();
    expect(wrapper.find('form').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.QUICK.closure_unavailable
    );
  });

  it('recovers a lost close response with the same key without repeating resolution or committing a duplicate', async () => {
    const committed = closureTransport({
      failClose: new Error('Synthetic network interruption'),
    });
    await renderClosure();
    await wrapper.get('textarea').setValue('Resolução sintética');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.QUICK.partial_closure
    );
    await wrapper
      .findAll('button')
      .find(
        button =>
          button.text() === messages.JRC_SERVICE_DESK.QUICK.recover_closure
      )
      .trigger('click');
    await flushPromises();
    expect(mocks.apply.mock.calls.map(row => row[2].rule_key)).toEqual([
      'resolve',
      'close',
      'close',
    ]);
    expect(mocks.apply.mock.calls[1][3]).toBe(mocks.apply.mock.calls[2][3]);
    expect(committed.size).toBe(2);
    expect(wrapper.emitted('updated')).toHaveLength(1);
  });

  it('requires only the extra fields actually mandated by the policy', async () => {
    closureTransport({
      extra: {
        ...requirements(),
        note: true,
        fields: {
          accepted: {
            label: 'Aceite contratual',
            type: 'boolean',
            required: true,
            equals: true,
          },
        },
      },
    });
    await renderClosure();
    expect(wrapper.findAll('textarea')).toHaveLength(2);
    await wrapper.findAll('textarea')[0].setValue('Resolução');
    expect(wrapper.get('button[type="submit"]').element.disabled).toBe(true);
    await wrapper.findAll('textarea')[1].setValue('Diagnóstico contratual');
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.apply.mock.calls[1][2].fields).toEqual({ accepted: true });
    expect(mocks.apply.mock.calls[1][2].note).toBe('Diagnóstico contratual');
  });

  it('preserves an older policy requiring a separate solution and never fills it from the reason silently', async () => {
    closureTransport({ extra: { ...requirements(), solution: true } });
    await renderClosure();
    expect(wrapper.findAll('textarea')).toHaveLength(2);
    await wrapper.findAll('textarea')[0].setValue('Motivo real informado');
    await wrapper.get('form').trigger('submit');
    expect(mocks.apply).not.toHaveBeenCalled();
    await wrapper
      .findAll('textarea')[1]
      .setValue('Solução específica da política antiga');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.apply.mock.calls[0][2]).not.toHaveProperty('solution');
    expect(mocks.apply.mock.calls[1][2].solution).toBe(
      'Solução específica da política antiga'
    );
    expect(mocks.apply.mock.calls[1][2].closing_reason).toBe(
      'Motivo real informado'
    );
    expect(wrapper.emitted('updated')).toHaveLength(1);
  });

  it('rejects a forged closure plan whose first step is not currently authorized', () => {
    expect(() =>
      decodeLifecycle(
        lcPayload({ closure_options: [{ key: 'close', steps: [close()] }] }),
        lcContext(),
        lcTicket()
      )
    ).toThrow();
  });

  it('shows the real SLA dependency without offering a command or manual SLA fields', async () => {
    mocks.read.mockResolvedValue(
      lcPayload({
        options: [],
        closure_options: [],
        unavailable_reason: 'calendar_snapshot_required',
      })
    );
    await renderClosure();
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.QUICK.calendar_snapshot_required
    );
    expect(wrapper.find('textarea').exists()).toBe(false);
    expect(mocks.apply).not.toHaveBeenCalled();
  });
});

async function renderQuick() {
  const ctx = lcContext();
  ctx.units = [
    { ...ctx.units[0], initial_status: { id: '1', name: 'Aberto' } },
  ];
  ctx.effective_permissions = ['jrc_service_desk_customers_view'];
  const mutation = reactive({ status: 'idle' });
  mocks.session = {
    state: reactive({ status: 'ready', context: ctx }),
    accountId: ref('1'),
    userId: ref('7'),
    operations: {
      mutation: () => mutation,
      dismissConfirmation: vi.fn(),
      cancel: vi.fn(),
      write: vi.fn(),
    },
    load: vi.fn(async () => {}),
    resource: () => ({ items: [{ id: '5', code: 'normal', name: 'Normal' }] }),
    resetResource: vi.fn(),
  };
  wrapper = mount(QuickTicketForm, { global: globals() });
  await flushPromises();
  return mutation;
}
async function fillQuick() {
  await wrapper.get('[data-company]').trigger('click');
  await wrapper.get('[data-resource="requesters"]').setValue('33');
  const inputs = wrapper.findAllComponents(Input);
  await inputs
    .find(row => row.props('label') === messages.JRC_SERVICE_DESK.FIELDS.title)
    .find('input')
    .setValue('Título sintético');
  await wrapper.get('textarea').setValue('Descrição sintética');
}

describe('quick intake without discarding advanced mode', () => {
  it('keeps small priority/type catalogues compact while enabling search for larger catalogues', async () => {
    await renderQuick();
    wrapper.unmount();
    const result = reactive({
      status: 'ready',
      items: [],
      meta: { total: 1, page: 1, per_page: 20 },
    });
    mocks.session.resource = () => result;
    wrapper = mount(NativeLookupSelect, {
      props: {
        unitId: '10',
        resource: 'priorities',
        label: 'Prioridade',
        compact: true,
      },
      global: {
        plugins: globals().plugins,
        stubs: { Input, Select: true, Button },
      },
    });
    await flushPromises();
    expect(wrapper.findComponent(Input).exists()).toBe(false);
    result.meta.total = 25;
    await flushPromises();
    expect(wrapper.findComponent(Input).exists()).toBe(true);
  });
  it('retains the real Normal priority when starting another ticket in the same unit', async () => {
    await renderQuick();
    await fillQuick();
    mocks.session.operations.write.mockResolvedValue(lcTicket());
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    const receipt = wrapper.findComponent({ name: 'TicketCreationReceipt' });
    receipt.vm.$emit('createAnother');
    await flushPromises();
    expect(wrapper.get('[data-resource="priorities"]').element.value).toBe('5');
  });

  it('saves a type preference only after confirmed creation and only for the current user and unit', async () => {
    await renderQuick();
    await fillQuick();
    await wrapper.get('[data-resource="ticket_types"]').setValue('6');
    wrapper.findComponent({ name: 'CatalogueAnswers' }).vm.$emit('ready', true);
    await wrapper.get('input[type="checkbox"]').setValue(true);
    mocks.session.operations.write.mockResolvedValue(lcTicket());
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(
      localStorage.getItem(
        ticketTypePreferenceKey(mocks.session.state.context, '10')
      )
    ).toBe('6');
    expect(
      localStorage.getItem(
        ticketTypePreferenceKey({ account_id: '2', user_id: '7' }, '10')
      )
    ).toBeNull();
  });

  it('restores an authorized advanced or relationship prefill without discarding its title or company', async () => {
    await renderQuick();
    await wrapper.setProps({
      initialDraft: {
        account_id: '1',
        user_id: '7',
        draft: {
          unit_id: '10',
          company_id: 80,
          requester_id: '33',
          title: 'Título preservado',
          description: 'Descrição preservada',
          priority_id: '',
          ticket_type_id: '',
          service_fields: {},
        },
        requester: { id: '33', name: 'Pessoa autorizada' },
      },
    });
    await flushPromises();
    expect(wrapper.get('[data-resource="requesters"]').element.value).toBe(
      '33'
    );
    expect(wrapper.get('[data-resource="priorities"]').element.value).toBe('5');
    expect(wrapper.get('textarea').element.value).toBe('Descrição preservada');
    await wrapper.setProps({
      initialDraft: {
        account_id: '2',
        user_id: '7',
        draft: { unit_id: '10', title: 'Foreign prefill' },
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('Foreign prefill');
  });
  it('preselects the only authorized unit and actual Normal priority, then submits minimal canonical fields', async () => {
    await renderQuick();
    await fillQuick();
    expect(wrapper.get('[data-resource="priorities"]').element.value).toBe('5');
    await wrapper.get('form').trigger('submit');
    expect(mocks.session.operations.write).toHaveBeenCalledWith(
      'ticket:quick:write',
      'create',
      expect.objectContaining({
        unit_id: '10',
        ticket: {
          title: 'Título sintético',
          description: 'Descrição sintética',
          requester_id: '33',
          company_id: '80',
          priority_id: '5',
          status_id: '1',
        },
      })
    );
  });

  it('passes company scope to the requester lookup and clears a previous person when company changes', async () => {
    await renderQuick();
    await fillQuick();
    expect(wrapper.findComponent(LookupSelect).props('companyId')).toBe(80);
    wrapper
      .findComponent({ name: 'CompanyPicker' })
      .vm.$emit('update:modelValue', 81);
    await flushPromises();
    expect(wrapper.get('[data-resource="requesters"]').element.value).toBe('');
  });

  it('creates a person in the official registry without leaving the form or writing a ticket', async () => {
    await renderQuick();
    await wrapper.get('[data-company]').trigger('click');
    await wrapper
      .findAll('button')
      .find(row => row.text() === messages.JRC_SERVICE_DESK.QUICK.new_requester)
      .trigger('click');
    await wrapper
      .findAllComponents(Input)
      .find(
        row =>
          row.props('label') === messages.JRC_SERVICE_DESK.QUICK.person_name
      )
      .find('input')
      .setValue('Nova pessoa sintética');
    mocks.saveContact.mockResolvedValue({
      data: {
        payload: { id: 33, company_id: 80, name: 'Nova pessoa sintética' },
      },
    });
    await wrapper
      .findAll('button')
      .find(
        row => row.text() === messages.JRC_SERVICE_DESK.QUICK.save_requester
      )
      .trigger('click');
    await flushPromises();
    expect(mocks.saveContact).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'Nova pessoa sintética',
        company_id: '80',
      })
    );
    expect(wrapper.get('[data-resource="requesters"]').element.value).toBe(
      '33'
    );
    expect(mocks.session.operations.write).not.toHaveBeenCalled();
  });

  it('makes the advanced workflow an explicit option and scopes the remembered type per Account, user and unit', async () => {
    await renderQuick();
    await wrapper
      .findAll('button')
      .find(row => row.text() === messages.JRC_SERVICE_DESK.QUICK.advanced)
      .trigger('click');
    expect(wrapper.emitted('advanced')).toHaveLength(1);
    const key = ticketTypePreferenceKey(mocks.session.state.context, '10');
    expect(key).not.toBe(
      ticketTypePreferenceKey({ account_id: '2', user_id: '7' }, '10')
    );
    expect(key).not.toBe(
      ticketTypePreferenceKey({ account_id: '1', user_id: '8' }, '10')
    );
  });

  it('shows an actionable company mismatch instead of the generic creation refusal', async () => {
    const mutation = await renderQuick();
    mutation.status = 'invalid_input';
    mutation.reason = 'requester_company_mismatch';
    await flushPromises();
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.QUICK.requester_company_mismatch
    );
  });

  it('accepts company filters only for the requester lookup and rejects malformed scope', () => {
    expect(normalizeQuery({ company_id: '80' }, 'requesters').company_id).toBe(
      '80'
    );
    expect(() => normalizeQuery({ company_id: '80' }, 'tickets')).toThrow();
    expect(() =>
      normalizeQuery({ company_id: '0080' }, 'requesters')
    ).toThrow();
  });
  it('sends the company filter through the real API adapter instead of filtering only a local page', async () => {
    const http = { get: vi.fn(async () => ({ data: {} })) };
    const client = createServiceDeskClient(http);
    await client.list('1', 'requesters', {
      unit_id: '10',
      company_id: '80',
      page: 2,
      per_page: 20,
    });
    expect(http.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_service_desk/requesters',
      expect.objectContaining({
        params: { unit_id: '10', company_id: '80', page: 2, per_page: 20 },
      })
    );
    expect(() =>
      client.list('1', 'priorities', { unit_id: '10', company_id: '80' })
    ).toThrow();
  });
});
