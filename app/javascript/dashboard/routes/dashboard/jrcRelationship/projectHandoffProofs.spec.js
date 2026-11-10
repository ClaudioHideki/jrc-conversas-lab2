import { mount, RouterLinkStub } from '@vue/test-utils';
import { expect, it, vi } from 'vitest';
import ProjectHandoffProofs from './ProjectHandoffProofs.vue';
import ResponsibilityComparison from './ResponsibilityComparison.vue';

vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => ({ params: { accountId: '42' } }),
}));

const rows = [
  {
    assignment_id: 5,
    label: 'Reviewed customer',
    entries: [],
    blockers: [],
    state: 'ready',
    project_handoffs: Array.from({ length: 12 }, (_, id) => ({
      id: id + 1,
      label: `Native project ${id + 1}`,
      state: id ? 'historical' : 'already_destination',
    })),
  },
];

it('shows the actual reviewed project states, native links and bounded pagination inside the comparison', async () => {
  const wrapper = mount(ResponsibilityComparison, {
    props: { rows },
    global: { stubs: { RouterLink: RouterLinkStub } },
  });
  const section = wrapper.findComponent(ProjectHandoffProofs);
  expect(section.findAll('[data-testid="project-handoff-proof"]')).toHaveLength(
    10
  );
  expect(section.text()).toContain('Reviewed customer');
  expect(section.text()).toContain(
    'Native project already belongs to the reviewed destination.'
  );
  expect(section.text()).toContain(
    'Historical project; original ownership is preserved.'
  );
  expect(section.findComponent(RouterLinkStub).props('to')).toEqual({
    name: 'jrc_projects_detail',
    params: { accountId: '42', projectId: 1 },
  });
  expect(section.findAll('button')[0].element.disabled).toBe(true);
  await section.findAll('button')[1].trigger('click');
  expect(section.findAll('[data-testid="project-handoff-proof"]')).toHaveLength(
    2
  );
  expect(section.text()).toContain('Native project 12');
  await wrapper.setProps({
    rows: [
      { ...rows[0], project_handoffs: rows[0].project_handoffs.slice(0, 1) },
    ],
  });
  expect(section.text()).toContain('Native project 1');
  expect(section.findAll('button')).toHaveLength(0);
  wrapper.unmount();
});

it('clears project identity and links when the responsibility scope is no longer available', async () => {
  const wrapper = mount(ProjectHandoffProofs, {
    props: { rows },
    global: { stubs: { RouterLink: RouterLinkStub } },
  });
  await wrapper.setProps({ rows: [{ ...rows[0], state: 'unavailable' }] });
  expect(wrapper.text()).not.toContain('Native project');
  expect(wrapper.findAllComponents(RouterLinkStub)).toHaveLength(0);
  wrapper.unmount();
});

it('leaves existing non-project responsibility proposals unchanged', () => {
  const wrapper = mount(ProjectHandoffProofs, {
    props: { rows: [{ ...rows[0], project_handoffs: undefined }] },
  });
  expect(wrapper.find('section').exists()).toBe(false);
  wrapper.unmount();
});
