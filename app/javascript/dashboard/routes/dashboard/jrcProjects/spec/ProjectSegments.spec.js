import { mount, flushPromises, RouterLinkStub } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import ProjectList from '../../jrcOperations/views/ProjectList.vue';

const mocks = vi.hoisted(() => ({
  request: vi.fn(),
  route: null,
  replace: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace, push: vi.fn() }),
}));
vi.mock('../useProjects', () => ({
  useProjects: () => ({
    accountId: ref('1'),
    userId: ref('2'),
    status: ref({ projects_enabled: true }),
    canCreate: ref(false),
    projectText: (key, fallback) => fallback,
  }),
}));
vi.mock('../../jrcOperations/api', async importOriginal => ({
  ...(await importOriginal()),
  request: mocks.request,
}));
const SegmentControl = {
  name: 'ProjectSegmentControl',
  props: ['moduleKey'],
  template: '<div />',
};
const project = {
  id: 7,
  name: 'Selected project',
  key: 'P-MOCK',
  status: 'planned',
  capabilities: ['projects.project.update'],
};
const render = () =>
  mount(ProjectList, {
    global: {
      stubs: {
        RouterLink: RouterLinkStub,
        ModuleSegmentFilter: SegmentControl,
        ProjectPortfolioSummary: true,
        CreateProject: true,
        DeleteProjectButton: true,
      },
    },
  });
const button = (wrapper, text) =>
  wrapper.findAll('button').find(item => item.text() === text);

beforeEach(() => {
  window.localStorage.removeItem('jrc:projects:portfolio:1:2');
  mocks.route = reactive({
    query: { customer_segment_id: '12', retained: 'yes' },
  });
  mocks.replace.mockImplementation(({ query }) => {
    mocks.route.query = query;
    return Promise.resolve();
  });
  mocks.request.mockImplementation(async (accountId, path) =>
    path === 'projects/portfolio'
      ? { data: { total: 13, filter_options: { owners: [], contacts: [] } } }
      : { data: [project], meta: { total: 13 } }
  );
});

it('uses the Projects catalog and the same segment for the list, portfolio and pagination', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.findComponent(SegmentControl).props('moduleKey')).toBe(
    'projects'
  );
  expect(mocks.request).toHaveBeenCalledWith('1', 'projects/projects', {
    params: expect.objectContaining({ customer_segment_id: '12', page: 1 }),
  });
  expect(mocks.request).toHaveBeenCalledWith('1', 'projects/portfolio', {
    params: { customer_segment_id: '12' },
  });
  await button(wrapper, 'Próxima').trigger('click');
  await flushPromises();
  expect(mocks.request).toHaveBeenLastCalledWith('1', 'projects/projects', {
    params: expect.objectContaining({ customer_segment_id: '12', page: 2 }),
  });
  wrapper.unmount();
});

it('resets pagination on segment changes and retains it in native detail and edit navigation', async () => {
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'Próxima').trigger('click');
  await flushPromises();
  mocks.route.query.customer_segment_id = '19';
  await flushPromises();
  expect(mocks.request).toHaveBeenCalledWith('1', 'projects/projects', {
    params: expect.objectContaining({ customer_segment_id: '19', page: 1 }),
  });
  const destinations = wrapper
    .findAllComponents(RouterLinkStub)
    .map(link => link.props('to'));
  expect(destinations).toContainEqual(
    expect.objectContaining({
      name: 'jrc_projects_detail',
      query: { customer_segment_id: '19' },
    })
  );
  expect(destinations).toContainEqual(
    expect.objectContaining({
      query: { customer_segment_id: '19', tab: 'settings' },
    })
  );
  wrapper.unmount();
});

it('clears the selected segment without discarding unrelated navigation parameters', async () => {
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'Limpar filtros').trigger('click');
  await flushPromises();
  expect(mocks.replace).toHaveBeenCalledWith({ query: { retained: 'yes' } });
  expect(mocks.request).toHaveBeenCalledWith('1', 'projects/portfolio', {
    params: { customer_segment_id: undefined },
  });
  expect(mocks.request).toHaveBeenCalledWith('1', 'projects/projects', {
    params: expect.objectContaining({
      customer_segment_id: undefined,
      page: 1,
    }),
  });
  wrapper.unmount();
});

it('does not display a late response from the previously selected segment', async () => {
  let finishOld;
  mocks.request.mockImplementation((accountId, path, options) => {
    if (path === 'projects/portfolio')
      return Promise.resolve({ data: { total: 0 } });
    if (options.params.customer_segment_id === '12') {
      return new Promise(resolve => {
        finishOld = resolve;
      });
    }
    return Promise.resolve({ data: [], meta: { total: 0 } });
  });
  const wrapper = render();
  await flushPromises();
  mocks.route.query.customer_segment_id = '19';
  await flushPromises();
  finishOld({ data: [project], meta: { total: 13 } });
  await flushPromises();
  expect(wrapper.text()).not.toContain('Selected project');
  expect(wrapper.text()).toContain('0');
  wrapper.unmount();
});
