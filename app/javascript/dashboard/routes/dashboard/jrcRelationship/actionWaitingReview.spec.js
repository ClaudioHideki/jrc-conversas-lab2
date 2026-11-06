import { mount } from '@vue/test-utils';
import { expect, it, vi } from 'vitest';
import Dialog from './ActionFollowUpDialog.vue';
import Editor from './RecordEditor.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const NativeDialog = {
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<section><slot /></section>',
};
const record = {
  id: 2,
  status: 'open',
  assignment_id: 4,
  reason: 'Native root cause',
  metadata: {},
};

it('navigates to the waiting review fields and refuses an incomplete pause, then emits the actual reason and future deadline', async () => {
  const wrapper = mount(Dialog, {
    props: { record },
    global: { stubs: { Dialog: NativeDialog } },
  });
  await wrapper
    .get('[data-testid="action-status"]')
    .setValue('waiting_customer');
  expect(wrapper.get('[data-action-tab="followup"]').isVisible()).toBe(true);
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')).toBeUndefined();
  expect(wrapper.text()).toContain('WAITING_REVIEW_REQUIRED');
  await wrapper
    .get('[data-testid="action-waiting-reason"]')
    .setValue('Awaiting diagnostic evidence');
  await wrapper
    .get('[data-testid="action-next-step"]')
    .setValue('Review evidence');
  const future = new Date(Date.now() + 86_400_000).toISOString().slice(0, 16);
  await wrapper.get('[data-testid="action-return-at"]').setValue(future);
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0]).toEqual(
    expect.objectContaining({
      status: 'waiting_customer',
      waiting_reason: 'Awaiting diagnostic evidence',
      next_step: 'Review evidence',
      return_at: new Date(future).toISOString(),
    })
  );
  wrapper.unmount();
});

it('preserves the persisted reason and blocks an expired or busy pause without emitting a false save', async () => {
  const wrapper = mount(Dialog, {
    props: {
      record: {
        ...record,
        status: 'waiting_finance',
        metadata: { waiting_reason: 'Native financial confirmation' },
        next_step: 'Review payment evidence',
        return_at: new Date(Date.now() - 86_400_000).toISOString(),
      },
    },
    global: { stubs: { Dialog: NativeDialog } },
  });
  expect(
    wrapper.get('[data-testid="action-waiting-reason"]').element.value
  ).toBe('Native financial confirmation');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')).toBeUndefined();
  await wrapper
    .get('[data-testid="action-return-at"]')
    .setValue(new Date(Date.now() + 86_400_000).toISOString().slice(0, 16));
  await wrapper.setProps({ busy: true });
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')).toBeUndefined();
  wrapper.unmount();
});

it('opens the actual invalid field tab instead of leaving a required hidden control unfocusable', async () => {
  const wrapper = mount(Dialog, {
    props: {
      record: { ...record, status: 'completed' },
      initialTab: 'followup',
    },
    global: { stubs: { Dialog: NativeDialog } },
  });
  await wrapper.get('textarea[required]').trigger('invalid');
  expect(wrapper.get('[data-action-tab="result"]').isVisible()).toBe(true);
  wrapper.unmount();
});

it('protects the existing generic editor as well as the follow-up popup and retains its unrelated metadata', async () => {
  const source = {
    ...record,
    status: 'waiting_customer',
    metadata: { waiting_reason: 'Existing pause reason', unrelated: true },
  };
  const before = structuredClone(source);
  const wrapper = mount(Editor, {
    props: {
      kind: 'actions',
      record: source,
      customers: [{ id: 4, name: 'Native customer' }],
      metadata: { owners: [] },
    },
    global: { stubs: { SlaSummary: true } },
  });
  expect(
    wrapper
      .findAll('textarea')
      .some(field => field.element.value === 'Existing pause reason')
  ).toBe(true);
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')).toBeUndefined();
  expect(wrapper.text()).toContain('WAITING_REVIEW_REQUIRED');
  await wrapper
    .get('[data-testid="relationship-field-next_step"]')
    .setValue('Review native evidence');
  await wrapper
    .get('[data-testid="relationship-field-return_at"]')
    .setValue(new Date(Date.now() + 86_400_000).toISOString().slice(0, 16));
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0]).toEqual(
    expect.objectContaining({
      waiting_reason: 'Existing pause reason',
      metadata: source.metadata,
    })
  );
  expect(source).toEqual(before);
  wrapper.unmount();
});
