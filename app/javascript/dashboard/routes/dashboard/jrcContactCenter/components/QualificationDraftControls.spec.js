import { afterEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, mount } from '@vue/test-utils';
import PendingQualificationForm from '../../inbox/PendingQualificationForm.vue';
import QualificationDraftReview from '../../inbox/QualificationDraftReview.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
enableAutoUnmount(afterEach);

describe('reused native pending qualification form', () => {
  it('permits an explicit incomplete draft while completion remains disabled', async () => {
    const wrapper = mount(PendingQualificationForm, {
      props: { canSave: true },
    });
    const buttons = wrapper.findAll('button');
    expect(buttons[0].element.disabled).toBe(false);
    expect(buttons[1].element.disabled).toBe(true);
    await buttons[0].trigger('click');
    expect(wrapper.emitted('save')).toHaveLength(1);
    expect(wrapper.emitted('complete')).toBeUndefined();
  });

  it('updates native reason, result and notes through the actual input controls', async () => {
    const wrapper = mount(PendingQualificationForm);
    const selects = wrapper.findAll('select');
    await selects[0].setValue('order');
    await selects[1].setValue('pending');
    await wrapper.get('textarea').setValue('SYNTHETIC unfinished answer');
    expect(wrapper.emitted('update:reason').at(-1)).toEqual(['order']);
    expect(wrapper.emitted('update:result').at(-1)).toEqual(['pending']);
    expect(wrapper.emitted('update:note').at(-1)).toEqual([
      'SYNTHETIC unfinished answer',
    ]);
  });

  it('emits completion only from its explicit action after the mandatory values are available', async () => {
    const wrapper = mount(PendingQualificationForm, {
      props: {
        reason: 'order',
        result: 'completed',
        note: 'SYNTHETIC final answer',
      },
    });
    expect(wrapper.emitted('complete')).toBeUndefined();
    await wrapper.findAll('button')[1].trigger('click');
    expect(wrapper.emitted('complete')).toHaveLength(1);
    expect(wrapper.emitted('save')).toBeUndefined();
    expect(wrapper.get('textarea').element.value).toBe(
      'SYNTHETIC final answer'
    );
  });

  it('disables editing and both write actions while its attendance or authority is unavailable', () => {
    const wrapper = mount(PendingQualificationForm, {
      props: {
        disabled: true,
        canSave: true,
        reason: 'order',
        result: 'completed',
      },
    });
    expect(
      wrapper
        .findAll('select, textarea, button')
        .every(control => control.element.disabled)
    ).toBe(true);
    expect(wrapper.emitted('save')).toBeUndefined();
    expect(wrapper.emitted('complete')).toBeUndefined();
  });

  it('keeps the local answer visible and prevents writing during a revision conflict', () => {
    const wrapper = mount(PendingQualificationForm, {
      props: {
        conflict: true,
        canSave: true,
        reason: 'order',
        result: 'pending',
        note: 'SYNTHETIC retained answer',
      },
    });
    expect(wrapper.get('textarea').element.value).toBe(
      'SYNTHETIC retained answer'
    );
    expect(
      wrapper.findAll('button').every(button => button.element.disabled)
    ).toBe(true);
    expect(wrapper.emitted('save')).toBeUndefined();
  });

  it('renders stored legacy codes as data and treats notes as text', () => {
    const note = '<img src=x onerror="synthetic()">';
    const wrapper = mount(PendingQualificationForm, {
      props: { reason: 'legacy-reason', result: 'legacy-result', note },
    });
    expect(
      wrapper.findAll('select').map(select => select.element.value)
    ).toEqual(['legacy-reason', 'legacy-result']);
    expect(wrapper.get('textarea').element.value).toBe(note);
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.get('textarea').attributes('maxlength')).toBe('4000');
  });

  it('shows a saved status only when the native caller reports persisted state', async () => {
    const wrapper = mount(PendingQualificationForm, { props: { saved: true } });
    expect(wrapper.get('[role="status"]').text()).toBe(
      'JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_SAVED'
    );
    await wrapper.setProps({ saved: false });
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
  });
});

describe('explicit native qualification conflict review', () => {
  it('shows current server answers without applying or saving them automatically', () => {
    const wrapper = mount(QualificationDraftReview, {
      props: {
        current: {
          reason_code: 'order',
          outcome_code: 'pending',
          notes: 'SYNTHETIC server answer',
        },
        canUseRemote: true,
        canReapply: true,
      },
    });
    expect(wrapper.text()).toContain('SYNTHETIC server answer');
    expect(wrapper.emitted()).toEqual({});
  });

  it('requires an explicit choice to use remote answers or review a local edit on the current revision', async () => {
    const wrapper = mount(QualificationDraftReview, {
      props: {
        current: { notes: 'SYNTHETIC current' },
        canUseRemote: true,
        canReapply: true,
      },
    });
    const buttons = wrapper.findAll('button');
    await buttons[1].trigger('click');
    expect(wrapper.emitted('useRemote')).toHaveLength(1);
    expect(wrapper.emitted('reapply')).toBeUndefined();
    await buttons[2].trigger('click');
    expect(wrapper.emitted('reapply')).toHaveLength(1);
  });

  it('blocks decisions until a current server observation is available', async () => {
    const wrapper = mount(QualificationDraftReview);
    const buttons = wrapper.findAll('button');
    expect(buttons[1].element.disabled).toBe(true);
    expect(buttons[2].element.disabled).toBe(true);
    await buttons[0].trigger('click');
    expect(wrapper.emitted('reload')).toHaveLength(1);
    expect(wrapper.emitted('useRemote')).toBeUndefined();
  });

  it('does not offer reapplication when the native attendance is no longer pending', () => {
    const wrapper = mount(QualificationDraftReview, {
      props: { current: null, canUseRemote: true },
    });
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_NO_PENDING'
    );
    expect(wrapper.findAll('button')[2].element.disabled).toBe(true);
  });

  it('disables all review actions while a current operation is in flight', () => {
    const wrapper = mount(QualificationDraftReview, {
      props: { busy: true, canUseRemote: true, canReapply: true },
    });
    expect(
      wrapper.findAll('button').every(button => button.element.disabled)
    ).toBe(true);
    expect(wrapper.emitted()).toEqual({});
  });
});
