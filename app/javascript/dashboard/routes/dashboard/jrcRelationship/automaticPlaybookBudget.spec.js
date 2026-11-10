import { mount } from '@vue/test-utils';
import { expect, it } from 'vitest';
import Notice from './AutomaticPlaybookNotice.vue';

it('shows the actual last deferred admission and changes reason without implying playbook completion', async () => {
  const attempt = {
    state: 'deferred',
    reason: 'account_daily_budget',
    required_actions: 2,
    attempted_at: '2026-11-05T23:30:00Z',
    eligible_after: '2026-11-06T03:00:00Z',
  };
  const wrapper = mount(Notice, { props: { attempt } });
  expect(
    wrapper
      .get('[data-testid="automatic-playbook-deferred"]')
      .attributes('role')
  ).toBe('status');
  expect(wrapper.text()).toContain('2');
  expect(wrapper.text()).toContain('does not guarantee execution');
  expect(wrapper.classes()).toContain('min-w-0');
  expect(wrapper.classes()).toContain('dark:bg-amber-950');
  await wrapper.setProps({
    attempt: { ...attempt, reason: 'native_assignment_unavailable' },
  });
  expect(wrapper.text()).toContain('available authorized analyst');
  expect(wrapper.find('button').exists()).toBe(false);
  wrapper.unmount();
});

it('hides a former deferral after another identity, missing data or a later admitted attempt', async () => {
  const wrapper = mount(Notice, { props: { attempt: { state: 'admitted' } } });
  expect(wrapper.find('[role="status"]').exists()).toBe(false);
  await wrapper.setProps({ attempt: null });
  expect(wrapper.find('[role="status"]').exists()).toBe(false);
  wrapper.unmount();
});
