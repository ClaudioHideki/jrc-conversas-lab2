import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import PendingQualificationForm from './PendingQualificationForm.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('native pending qualification registered reason options', () => {
  it('locks only confirmed classification and keeps remaining draft fields and context retry available', async () => {
    const wrapper = mount(PendingQualificationForm, {
      props: {
        reason: 'order',
        reasonRevision: 2,
        reasonRequired: true,
        reasonOptions: [{ code: 'order', name: 'SYNTHETIC registered' }],
        formError: true,
        reasonConfirmation: {
          state: 'confirmed',
          reason_code: 'order',
          reason_label: 'SYNTHETIC confirmed',
        },
      },
      global: { stubs: { EndingReasonConfirmation: true } },
    });
    expect(
      wrapper.get('[data-qualification-field="reason"]').element.disabled
    ).toBe(true);
    expect(
      wrapper.get('[data-qualification-field="result"]').element.disabled
    ).toBe(false);
    expect(
      wrapper.get('[data-qualification-field="note"]').element.disabled
    ).toBe(false);
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.ENDING_REASONS.OPERATIONAL_REQUIRED'
    );
    await wrapper.get('[data-reload-ending-context]').trigger('click');
    expect(wrapper.emitted('reloadForm')).toHaveLength(1);
    await wrapper.setProps({ reasonConfirmation: null });
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.ENDING_REASONS.OPERATIONAL_REQUIRED'
    );
    expect(
      wrapper.get('[data-qualification-field="reason"]').element.disabled
    ).toBe(false);
    wrapper.unmount();
  });

  it('offers exactly the frozen registered choices for a required queue and preserves their order', () => {
    const wrapper = mount(PendingQualificationForm, {
      props: {
        reasonRequired: true,
        reasonRevision: 2,
        reason: 'resolved',
        reasonOptions: [
          { code: '20', name: 'SYNTHETIC first' },
          { code: '3', name: 'SYNTHETIC second' },
          { code: '__proto__', name: 'SYNTHETIC literal' },
        ],
      },
    });
    const options = wrapper.findAll(
      '[data-qualification-field="reason"] option'
    );
    expect(options.map(row => row.element.value)).toEqual([
      '',
      '20',
      '3',
      '__proto__',
    ]);
    expect(options.map(row => row.text())).toContain('SYNTHETIC literal');
    expect(wrapper.find('[data-qualification-form-context]').exists()).toBe(
      false
    );
    expect(wrapper.get('[data-ending-reason-version]').isVisible()).toBe(true);
    wrapper.unmount();
  });

  it('preserves the legacy options and an old manually saved choice outside required queues', () => {
    const wrapper = mount(PendingQualificationForm, {
      props: {
        reason: 'historical',
        reasonOptions: [{ code: 'order', name: 'SYNTHETIC frozen order' }],
      },
    });
    const options = wrapper.findAll(
      '[data-qualification-field="reason"] option'
    );
    expect(options.map(row => row.element.value)).toContain('historical');
    expect(options.map(row => row.element.value)).toContain('resolved');
    expect(options.filter(row => row.element.value === 'order')).toHaveLength(
      1
    );
    expect(options.find(row => row.element.value === 'order').text()).toBe(
      'SYNTHETIC frozen order'
    );
    wrapper.unmount();
  });

  it('shows a real retry action when an ending-only context fails without pretending a form exists', async () => {
    const wrapper = mount(PendingQualificationForm, {
      props: {
        reasonRevision: 2,
        reasonRequired: true,
        formError: true,
        formReady: false,
      },
    });
    expect(
      wrapper.get('[data-ending-context-status] [role="alert"]').isVisible()
    ).toBe(true);
    expect(wrapper.find('[data-qualification-form-context]').exists()).toBe(
      false
    );
    await wrapper.get('[data-reload-ending-context]').trigger('click');
    expect(wrapper.emitted('reloadForm')).toHaveLength(1);
    wrapper.unmount();
  });
});
