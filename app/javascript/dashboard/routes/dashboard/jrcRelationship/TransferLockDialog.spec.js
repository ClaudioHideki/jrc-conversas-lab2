import { mount } from '@vue/test-utils';
import { expect, it, vi } from 'vitest';
import TransferLock from './TransferLockDialog.vue';

const NativeDialog = {
  setup(_, { expose, emit }) {
    expose({ open: vi.fn(), close: () => emit('close') });
  },
  template: '<section><slot /></section>',
};
const record = {
  id: 19,
  assignment_version: '2026-11-06T12:00:00.123456Z',
  transfer_locked: false,
  settings: {},
};
const editor = props =>
  mount(TransferLock, {
    props: { record, ...props },
    global: { stubs: { Dialog: NativeDialog } },
  });

it('requires a reason and emits an explicit boolean and captured revision without mutating the record', async () => {
  const before = structuredClone(record);
  const wrapper = editor();
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')).toBeUndefined();
  await wrapper.get('[data-testid="transfer-locked"]').setValue(true);
  await wrapper.get('textarea').setValue('  Synthetic strategic continuity  ');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0]).toEqual({
    locked: true,
    reason: 'Synthetic strategic continuity',
    expected_version: record.assignment_version,
  });
  expect(record).toEqual(before);
  wrapper.unmount();
});

it('requires a fresh justification when releasing an existing restriction', async () => {
  const wrapper = editor({
    record: {
      ...record,
      transfer_locked: true,
      settings: { transfer_lock: { reason: 'Previous native restriction' } },
    },
  });
  await wrapper.get('[data-testid="transfer-locked"]').setValue(false);
  await wrapper.get('textarea').setValue('');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')).toBeUndefined();
  await wrapper.get('textarea').setValue('Synthetic reviewed release');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0]).toMatchObject({
    locked: false,
    reason: 'Synthetic reviewed release',
  });
  wrapper.unmount();
});

it('keeps the draft and revision after a conflict and does not emit duplicate work while busy', async () => {
  const wrapper = editor();
  await wrapper.get('textarea').setValue('Synthetic preserved justification');
  await wrapper.setProps({ busy: true });
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')).toBeUndefined();
  await wrapper.setProps({
    busy: false,
    error: 'Record changed. Refresh before retrying.',
  });
  expect(wrapper.get('textarea').element.value).toBe(
    'Synthetic preserved justification'
  );
  expect(wrapper.get('[role="alert"]').text()).toContain('Record changed');
  expect(wrapper.emitted('close')).toBeUndefined();
  wrapper.unmount();
});

it('does not submit a record missing its optimistic revision or an oversized reason', async () => {
  const wrapper = editor({
    record: { ...record, assignment_version: undefined },
  });
  await wrapper.get('textarea').setValue('Synthetic justification');
  await wrapper.get('form').trigger('submit');
  expect(
    wrapper.get('button[type="submit"]').attributes('disabled')
  ).toBeDefined();
  expect(wrapper.emitted('save')).toBeUndefined();
  await wrapper.setProps({ record });
  await wrapper.get('textarea').setValue('x'.repeat(4001));
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')).toBeUndefined();
  wrapper.unmount();
});
