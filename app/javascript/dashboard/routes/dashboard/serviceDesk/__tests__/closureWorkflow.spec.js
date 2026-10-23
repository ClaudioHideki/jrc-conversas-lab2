import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import { lcContext, lcPayload, lcTicket, lcTransition } from './lifecycleCases';
import { detail, ticket, deferred } from './fixtures';

const holder = vi.hoisted(() => ({
  session: null,
  read: vi.fn(),
  apply: vi.fn(),
  transition: vi.fn(),
  ticket: vi.fn(),
}));
vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => holder.session,
}));
vi.mock('dashboard/api/serviceDeskLifecycle', () => ({
  default: {
    read: (...args) => holder.read(...args),
    apply: (...args) => holder.apply(...args),
    transition: (...args) => holder.transition(...args),
    ticket: (...args) => holder.ticket(...args),
  },
}));
import LifecyclePanel from '../components/LifecyclePanel.vue';

const Button = {
  props: ['label', 'disabled'],
  template: '<button :disabled="disabled">{{ label }}</button>',
};
const TextArea = {
  props: ['modelValue', 'label', 'disabled'],
  emits: ['update:modelValue'],
  template:
    '<label>{{ label }}<textarea :disabled="disabled" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>',
};
let wrapper;
beforeEach(() => {
  holder.session = {
    state: reactive({ status: 'ready', context: lcContext() }),
    operations: { state: reactive({ revision: 0 }) },
  };
  holder.read.mockResolvedValue(lcPayload());
});
afterEach(() => {
  wrapper?.unmount();
  vi.resetAllMocks();
});

const mountClosure = async () => {
  wrapper = mount(LifecyclePanel, {
    props: { ticket: lcTicket(), mode: 'closure' },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        Button,
        TextArea,
        Panel: { template: '<section><slot /></section>' },
        State: { props: ['status'], template: '<div :data-state="status" />' },
        Select: true,
        Input: true,
        Pagination: true,
      },
    },
  });
  await flushPromises();
};
const completeRequiredFields = async () => {
  await wrapper.findAll('textarea')[0].setValue('Diagnóstico sintético');
  await wrapper.findAll('textarea')[1].setValue('Solução sintética');
  wrapper.findComponent({ name: 'Input' }).vm.$emit('update:modelValue', '7');
  await wrapper
    .get('[data-testid="lifecycle-boolean-field"] input')
    .setValue(true);
  await wrapper
    .findAll('form > label input[type="checkbox"]')
    .at(-1)
    .setValue(true);
  await flushPromises();
};
const successfulReadback = action => {
  holder.apply.mockImplementation(async (_account, _ticket, command, key) => {
    holder.transition.mockResolvedValue({
      contract_version: 1,
      account_id: '1',
      transition: lcTransition({
        action,
        rule_key: command.rule_key,
        request_key: key,
        payload: { ...command, sla: { cycle_id: null } },
      }),
    });
    holder.ticket.mockResolvedValue(
      detail(
        ticket({
          lock_version: 1,
          status: { id: '2', name: 'Estado persistido' },
        })
      )
    );
    holder.read.mockResolvedValue(lcPayload({ lock_version: 1, options: [] }));
    return {
      contract_version: 1,
      account_id: '1',
      applied: true,
      operation: 'lifecycle',
      ticket_id: '20',
      result_id: '80',
    };
  });
};

describe('native closure modal and official lifecycle session', () => {
  it('requires diagnosis, solution, evidence, policy fields and explicit confirmation', async () => {
    await mountClosure();
    expect(wrapper.get('button[type="submit"]').element.disabled).toBe(true);
    await wrapper.get('form').trigger('submit');
    expect(holder.apply).not.toHaveBeenCalled();
    await completeRequiredFields();
    expect(wrapper.get('button[type="submit"]').element.disabled).toBe(false);
  });

  it('resolves first and emits success only after transition, ticket and lifecycle rereads', async () => {
    successfulReadback('resolve');
    await mountClosure();
    expect(wrapper.get('button[type="submit"]').text()).toBe(
      messages.JRC_SERVICE_DESK.REFINEMENT.closure.resolve
    );
    await completeRequiredFields();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(holder.apply).toHaveBeenCalledTimes(1);
    expect(holder.apply.mock.calls[0][2].rule_key).toBe('resolve');
    expect(holder.transition).toHaveBeenCalledTimes(1);
    expect(holder.ticket).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted('updated')).toHaveLength(1);
    expect(holder.session.operations.state.revision).toBe(1);
  });

  it('closes only when a close transition is explicitly offered', async () => {
    const payload = lcPayload();
    payload.options[0].key = 'close';
    payload.options[0].action = 'close';
    holder.read.mockResolvedValue(payload);
    successfulReadback('close');
    await mountClosure();
    await completeRequiredFields();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(holder.apply.mock.calls[0][2].rule_key).toBe('close');
    expect(wrapper.emitted('updated')).toHaveLength(1);
  });

  it('cannot submit without an applicable policy', async () => {
    holder.read.mockResolvedValue(
      lcPayload({
        policy: null,
        options: [],
        unavailable_reason: 'no_applicable_policy',
      })
    );
    await mountClosure();
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.LIFECYCLE.no_applicable_policy
    );
    expect(wrapper.find('form').exists()).toBe(false);
    expect(holder.apply).not.toHaveBeenCalled();
  });

  it('cannot submit when lifecycle inspection is denied', async () => {
    holder.read.mockRejectedValue({ response: { status: 403 } });
    await mountClosure();
    expect(wrapper.get('[data-state]').attributes('data-state')).toBe('denied');
    expect(wrapper.find('form').exists()).toBe(false);
    expect(holder.apply).not.toHaveBeenCalled();
  });

  it('coalesces repeated submission while the request is in flight', async () => {
    const pending = deferred();
    holder.apply.mockReturnValue(pending.promise);
    await mountClosure();
    await completeRequiredFields();
    await wrapper.get('form').trigger('submit');
    await wrapper.get('form').trigger('submit');
    expect(holder.apply).toHaveBeenCalledTimes(1);
    expect(wrapper.get('button[type="submit"]').element.disabled).toBe(true);
    pending.reject(new Error('Synthetic connection loss'));
    await flushPromises();
    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(wrapper.emitted('busyChange').at(-1)).toEqual([true]);
  });

  it('preserves the same key and payload when recovering an uncertain API result', async () => {
    holder.apply.mockRejectedValue(new Error('Synthetic API failure'));
    await mountClosure();
    await completeRequiredFields();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    const first = holder.apply.mock.calls[0];
    expect(wrapper.emitted('updated')).toBeUndefined();
    successfulReadback('resolve');
    await wrapper
      .findAll('button')
      .find(row => row.text() === messages.JRC_SERVICE_DESK.LIFECYCLE.recover)
      .trigger('click');
    await flushPromises();
    expect(holder.apply.mock.calls[1].slice(0, 4)).toEqual(first.slice(0, 4));
    expect(wrapper.emitted('updated')).toHaveLength(1);
  });

  it('shows a policy/version conflict without reporting closure', async () => {
    holder.apply.mockRejectedValue({ response: { status: 409 } });
    await mountClosure();
    await completeRequiredFields();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.LIFECYCLE.feedback.conflict
    );
    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(holder.ticket).not.toHaveBeenCalled();
  });

  it('does not confirm an ACK whose independent ticket reread fails', async () => {
    successfulReadback('resolve');
    holder.ticket.mockRejectedValueOnce(
      new Error('Synthetic reread unavailable')
    );
    await mountClosure();
    await completeRequiredFields();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.LIFECYCLE.feedback.readback_pending
    );
    expect(wrapper.emitted('busyChange').at(-1)).toEqual([true]);
  });
});
