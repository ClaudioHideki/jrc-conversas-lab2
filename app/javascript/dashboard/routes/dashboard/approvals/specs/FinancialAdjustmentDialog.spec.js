import { mount } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import FinancialAdjustmentDialog from '../FinancialAdjustmentDialog.vue';

const DialogStub = defineComponent({
  props: { disableConfirmButton: Boolean, isLoading: Boolean },
  emits: ['confirm'],
  setup(props, { expose, emit, slots }) {
    expose({ open: vi.fn() });
    return () =>
      h('div', [
        slots.default?.(),
        h(
          'button',
          {
            'data-testid': 'confirm-adjustment',
            disabled: props.disableConfirmButton || props.isLoading,
            onClick: () => emit('confirm'),
          },
          'Confirm'
        ),
      ]);
  },
});

let wrapper;
let request;
beforeEach(() => {
  request = {
    id: 71,
    lock_version: 3,
    state: 'pending',
    adjustment: {
      values: { installments_count: 2 },
      fields: { installments_count: { min: 1, max: 12 } },
    },
    allowed_decisions: [],
  };
});
afterEach(() => wrapper?.unmount());

describe('configured financial adjustment dialog', () => {
  const render = () => {
    wrapper = mount(FinancialAdjustmentDialog, {
      props: { request },
      global: { stubs: { Dialog: DialogStub } },
    });
  };

  const changeTerms = async () => {
    await wrapper.get('input[type="number"]').setValue('6');
    await wrapper.get('textarea').setValue('Synthetic authorized correction');
  };

  it('does not mutate the original terms or submit just by opening', () => {
    render();
    expect(
      wrapper.get('[data-testid="confirm-adjustment"]').element.disabled
    ).toBe(true);
    expect(wrapper.emitted('confirm')).toBeUndefined();
    expect(request.adjustment.values.installments_count).toBe(2);
  });

  it('emits only changed configured fields, reason and captured revision', async () => {
    render();
    await changeTerms();
    await wrapper.get('[data-testid="confirm-adjustment"]').trigger('click');
    expect(wrapper.emitted('confirm')).toEqual([
      [
        {
          changes: { installments_count: 6 },
          reason: 'Synthetic authorized correction',
          mode: 'save',
          expected_version: 3,
        },
      ],
    ]);
    expect(request.adjustment.values.installments_count).toBe(2);
  });

  it('blocks values outside the limits supplied by the native policy', async () => {
    render();
    await changeTerms();
    await wrapper.get('input[type="number"]').setValue('13');
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(
      wrapper.get('[data-testid="confirm-adjustment"]').element.disabled
    ).toBe(true);
  });

  it('cannot save and approve without an authorized native decision choice', async () => {
    render();
    await changeTerms();
    await wrapper.get('select').setValue('approve');
    expect(
      wrapper.get('[data-testid="confirm-adjustment"]').element.disabled
    ).toBe(true);
    await wrapper.get('[data-testid="confirm-adjustment"]').trigger('click');
    expect(wrapper.emitted('confirm')).toBeUndefined();
  });

  it('forwards the explicit approval choice without inventing another level', async () => {
    request.allowed_decisions = [
      {
        step_code: 'synthetic-financial',
        choices: [
          { actions: ['approved'], delegation_id: 21, own_delegation_id: 32 },
        ],
      },
    ];
    render();
    await changeTerms();
    await wrapper.get('select').setValue('approve');
    await wrapper.get('[data-testid="confirm-adjustment"]').trigger('click');
    expect(wrapper.emitted('confirm')[0][0]).toMatchObject({
      mode: 'approve',
      expected_version: 3,
      step_code: 'synthetic-financial',
      delegation_id: 21,
      own_delegation_id: 32,
    });
  });

  it('refuses a draft whose source revision changed while the dialog was open', async () => {
    render();
    await changeTerms();
    await wrapper.setProps({ request: { ...request, lock_version: 4 } });
    expect(
      wrapper.get('[data-testid="confirm-adjustment"]').element.disabled
    ).toBe(true);
    await wrapper.get('[data-testid="confirm-adjustment"]').trigger('click');
    expect(wrapper.emitted('confirm')).toBeUndefined();
  });

  it('clears fields and requests closing after a native access denial', async () => {
    render();
    await changeTerms();
    await wrapper.setProps({ errorState: { status: 403 } });
    expect(wrapper.find('input[type="number"]').exists()).toBe(false);
    expect(wrapper.get('textarea').element.value).toBe('');
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(wrapper.emitted('confirm')).toBeUndefined();
  });
});
