import { afterEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, mount } from '@vue/test-utils';
import EndingReasonConfirmation from './EndingReasonConfirmation.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
enableAutoUnmount(afterEach);
const Dialog = defineComponent({
  props: { disableConfirmButton: Boolean },
  emits: ['confirm'],
  setup(props, { expose, emit, slots }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
      close: () => {
        visible.value = false;
      },
    });
    return () =>
      visible.value
        ? h('section', { 'data-review-dialog': '' }, [
            slots.default?.(),
            h('button', {
              'data-confirm': '',
              disabled: props.disableConfirmButton,
              onClick: () => emit('confirm'),
            }),
          ])
        : null;
  },
});
const render = (changes = {}) =>
  mount(EndingReasonConfirmation, {
    props: {
      scope: 'SYNTHETIC account1/actor9/call22',
      reason: 'registered',
      label: 'SYNTHETIC registered',
      canConfirm: true,
      ...changes,
    },
    global: { stubs: { Dialog } },
  });

describe('Ending classification requires explicit operator confirmation', () => {
  it('opens review without submitting and emits once only after confirmation', async () => {
    const wrapper = render();
    await wrapper.get('[data-confirm-ending-reason]').trigger('click');
    expect(wrapper.get('[data-review-dialog]').text()).toContain(
      'SYNTHETIC registered'
    );
    expect(wrapper.emitted('confirm')).toBeUndefined();
    await wrapper.get('[data-confirm]').trigger('click');
    await wrapper.get('[data-confirm]').trigger('click');
    expect(wrapper.emitted('confirm')).toHaveLength(1);
  });

  it('closes an open review on an attendance change without confirming the next attendance', async () => {
    const wrapper = render();
    await wrapper.get('[data-confirm-ending-reason]').trigger('click');
    await wrapper.setProps({ scope: 'SYNTHETIC account2/actor20/call33' });
    expect(wrapper.find('[data-review-dialog]').exists()).toBe(false);
    expect(wrapper.emitted('confirm')).toBeUndefined();
  });

  it('closes stale review after the reason changes and requires another explicit review', async () => {
    const wrapper = render();
    await wrapper.get('[data-confirm-ending-reason]').trigger('click');
    await wrapper.setProps({
      reason: 'other',
      label: 'SYNTHETIC another reason',
    });
    expect(wrapper.find('[data-review-dialog]').exists()).toBe(false);
    await wrapper.get('[data-confirm-ending-reason]').trigger('click');
    expect(wrapper.get('[data-review-dialog]').text()).toContain(
      'SYNTHETIC another reason'
    );
    expect(wrapper.emitted('confirm')).toBeUndefined();
  });

  it.each([{ busy: true }, { disabled: true }, { canConfirm: false }])(
    'cannot open an unavailable confirmation %j',
    async changes => {
      const wrapper = render(changes);
      await wrapper.get('[data-confirm-ending-reason]').trigger('click');
      expect(wrapper.find('[data-review-dialog]').exists()).toBe(false);
      expect(wrapper.emitted('confirm')).toBeUndefined();
    }
  );

  it('offers no second confirmation once the server has persisted classification', () => {
    const wrapper = render({
      confirmation: {
        state: 'confirmed',
        reason_label: 'SYNTHETIC registered',
      },
    });
    expect(wrapper.find('[data-ending-reason-confirmed]').exists()).toBe(true);
    expect(wrapper.find('[data-confirm-ending-reason]').exists()).toBe(false);
    expect(wrapper.emitted('confirm')).toBeUndefined();
  });

  it('allows an explicit retry after a finished failed request, without resubmitting automatically', async () => {
    const wrapper = render();
    await wrapper.get('[data-confirm-ending-reason]').trigger('click');
    await wrapper.get('[data-confirm]').trigger('click');
    await wrapper.setProps({ busy: true });
    await wrapper.setProps({ busy: false, error: true });
    expect(wrapper.emitted('confirm')).toHaveLength(1);
    expect(wrapper.get('[role="alert"]').exists()).toBe(true);
    await wrapper.get('[data-confirm]').trigger('click');
    expect(wrapper.emitted('confirm')).toHaveLength(2);
  });
});
