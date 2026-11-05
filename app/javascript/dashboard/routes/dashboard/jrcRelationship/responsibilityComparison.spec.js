import { mount } from '@vue/test-utils';
import { expect, it } from 'vitest';
import ResponsibilityComparison from './ResponsibilityComparison.vue';

it('paginates the actual frozen responsibilities and resets after a proposal change', async () => {
  const entries = Array.from({ length: 12 }, (_, id) => ({
    id,
    kind: 'actions',
    label: `Synthetic responsibility ${id}`,
    from_owner_name: 'Original analyst',
  }));
  const wrapper = mount(ResponsibilityComparison, {
    props: {
      ownerName: 'Reviewed analyst',
      rows: [{ assignment_id: 4, entries, blockers: [], state: 'ready' }],
    },
  });
  expect(wrapper.findAll('article')).toHaveLength(10);
  expect(wrapper.text()).toContain('Original analyst');
  expect(wrapper.text()).toContain('Reviewed analyst');
  expect(wrapper.findAll('button')[0].element.disabled).toBe(true);
  await wrapper.findAll('button')[1].trigger('click');
  expect(wrapper.findAll('article')).toHaveLength(2);
  expect(wrapper.findAll('button')[1].element.disabled).toBe(true);
  await wrapper.setProps({
    rows: [
      {
        assignment_id: 7,
        entries: entries.slice(0, 1),
        blockers: [],
        state: 'canceled',
      },
    ],
  });
  expect(wrapper.text()).toContain('Synthetic responsibility 0');
  expect(wrapper.findAll('[role="alert"]')).toHaveLength(1);
  expect(wrapper.findAll('button')).toHaveLength(0);
  wrapper.unmount();
});

it.each(['blocked', 'stale', 'unavailable', 'failed', 'canceled'])(
  'shows %s as an alert without invented transfers or hidden details',
  state => {
    const wrapper = mount(ResponsibilityComparison, {
      props: {
        rows: [
          {
            assignment_id: 4,
            entries: [],
            blockers: ['responsibility_scope_denied'],
            state,
          },
        ],
      },
    });
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(wrapper.findAll('article')).toHaveLength(0);
    expect(wrapper.text()).not.toContain('STATES.executed');
    wrapper.unmount();
  }
);
