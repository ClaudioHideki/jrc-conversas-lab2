import { shallowMount, flushPromises } from '@vue/test-utils';
import { expect, it } from 'vitest';
import Editor from './RecordEditor.vue';
import Context from './WorkContextPanel.vue';

const metadata = {
  can_team: true,
  owners: [
    [7, 'Previous analyst'],
    [8, 'Unrelated account analyst'],
  ],
};
const record = {
  id: 31,
  assignment_id: 19,
  owner_id: 7,
  owner_name: 'Previous analyst',
  reason: 'Synthetic work',
  status: 'pending',
};
const context = {
  period: { from: '2026-10-01', to: '2026-11-01' },
  work_owners: [[9, 'Authorized working analyst']],
};
const mountEditor = props =>
  shallowMount(Editor, {
    props: { kind: 'actions', record, metadata, ...props },
  });

it('disables ownership selection until the assignment context arrives and avoids global candidates', async () => {
  const wrapper = mountEditor();
  const select = wrapper.get('[data-testid="work-owner"]');
  expect(select.attributes('disabled')).toBeDefined();
  expect(select.text()).not.toContain('Unrelated account analyst');
  wrapper.getComponent(Context).vm.$emit('loaded', context);
  await flushPromises();
  expect(select.attributes('disabled')).toBeUndefined();
  expect(select.text()).toContain('Authorized working analyst');
  expect(select.get('option[value="7"]').attributes('disabled')).toBeDefined();
  await select.setValue('9');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0].owner_id).toBe(9);
  wrapper.unmount();
});

it('retains the unchanged historical owner during an unrelated edit', async () => {
  const wrapper = mountEditor();
  wrapper.getComponent(Context).vm.$emit('loaded', context);
  await flushPromises();
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0].owner_id).toBe(7);
  wrapper.unmount();
});

it('clears a new-record target and old candidates when the customer changes', async () => {
  const wrapper = mountEditor({
    record: { assignment_id: 19 },
    customers: [
      { id: 19, name: 'One' },
      { id: 20, name: 'Two' },
    ],
  });
  wrapper.getComponent(Context).vm.$emit('loaded', context);
  await flushPromises();
  await wrapper.get('[data-testid="work-owner"]').setValue('9');
  await wrapper.get('select[required]').setValue('20');
  expect(
    wrapper.get('[data-testid="work-owner"]').attributes('disabled')
  ).toBeDefined();
  expect(wrapper.get('[data-testid="work-owner"]').text()).not.toContain(
    'Authorized working analyst'
  );
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0]).not.toHaveProperty('owner_id');
  wrapper.unmount();
});

it('keeps team permission required after the context arrives', async () => {
  const wrapper = mountEditor({ metadata: { ...metadata, can_team: false } });
  wrapper.getComponent(Context).vm.$emit('loaded', context);
  await flushPromises();
  expect(
    wrapper.get('[data-testid="work-owner"]').attributes('disabled')
  ).toBeDefined();
  wrapper.unmount();
});

it('scopes commitment owners while retaining historical labels and independent participant choices', async () => {
  const wrapper = mountEditor({
    kind: 'qbrs',
    record: {
      ...record,
      title: 'Synthetic QBR',
      scheduled_at: '2026-11-07T12:00:00Z',
      decisions: [{ decision_key: 'review', title: 'Follow up', owner_id: 7 }],
      participants: [{ participant_type: 'internal', user_id: 8 }],
    },
  });
  wrapper.getComponent(Context).vm.$emit('loaded', context);
  await flushPromises();
  const select = wrapper.get('[data-testid="commitment-owner"]');
  expect(select.get('option[value="7"]').attributes('disabled')).toBeDefined();
  expect(select.text()).toContain('Authorized working analyst');
  expect(select.text()).not.toContain('Unrelated account analyst');
  expect(wrapper.findAll('option[value="8"]').length).toBeGreaterThan(0);
  await select.setValue('9');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0].decisions[0]).toMatchObject({
    decision_key: 'review',
    owner_id: 9,
  });
  wrapper.unmount();
});
