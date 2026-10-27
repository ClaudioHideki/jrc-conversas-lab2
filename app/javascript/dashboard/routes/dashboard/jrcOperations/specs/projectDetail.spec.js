import { reactive, ref } from 'vue';
import { shallowMount, flushPromises } from '@vue/test-utils';
import ProjectDetail from '../views/ProjectDetail.vue';
import ProjectExecution from '../../jrcProjects/components/ProjectExecution.vue';
import { useProjects } from '../../jrcProjects/useProjects';
import { useRoute } from 'vue-router';
import { request, allPages } from '../api';

vi.mock('vue-router', () => ({
  useRoute: vi.fn(),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));
vi.mock('../../jrcProjects/useProjects', () => ({ useProjects: vi.fn() }));
vi.mock('../api', async importOriginal => ({
  ...(await importOriginal()),
  request: vi.fn(),
  allPages: vi.fn(),
}));

const project = {
  id: 7,
  key: 'PR-7',
  name: 'Authorized project',
  status: 'active',
  priority: 'medium',
  capabilities: [],
  columns: [],
  members: [],
  tasks_completed: 0,
  tasks_total: 2,
  progress: 0,
};
const tasks = [
  { id: 21, title: 'First' },
  { id: 22, title: 'Last page' },
];
function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}

describe('Project detail progressive loading', () => {
  let route;
  let accountId;
  let wrapper;
  beforeEach(() => {
    localStorage.clear();
    route = reactive({ params: { projectId: '7' }, query: { tab: 'board' } });
    accountId = ref(1);
    useRoute.mockReturnValue(route);
    useProjects.mockReturnValue({
      accountId,
      userId: ref(10),
      status: ref({ projects_enabled: true }),
      projectText: (key, fallback) => fallback,
    });
    request.mockResolvedValue({ data: project });
    allPages.mockResolvedValue(tasks);
  });
  afterEach(() => wrapper?.unmount());

  it('shows authorized project identity while all task pages are still pending', async () => {
    const pending = deferred();
    allPages.mockReturnValue(pending.promise);
    wrapper = shallowMount(ProjectDetail, {
      global: { stubs: { KeepAlive: false, RouterLink: true } },
    });
    await flushPromises();
    expect(wrapper.get('h1').text()).toBe('Authorized project');
    expect(wrapper.get('[role="tabpanel"]').attributes('aria-busy')).toBe(
      'true'
    );
    expect(wrapper.findComponent(ProjectExecution).props('synced')).toBe(false);
    pending.resolve(tasks);
    await flushPromises();
    expect(wrapper.get('[role="tabpanel"]').attributes('aria-busy')).toBe(
      'false'
    );
    expect(wrapper.findComponent(ProjectExecution).props('tasks')).toEqual(
      tasks
    );
    expect(wrapper.findComponent(ProjectExecution).props('synced')).toBe(true);
  });

  it.each(['project', 'account'])(
    'discards pending project and tasks after a %s change',
    async identity => {
      const oldProject = deferred();
      const oldTasks = deferred();
      const newTasks = deferred();
      request.mockReturnValueOnce(oldProject.promise);
      allPages
        .mockReturnValueOnce(oldTasks.promise)
        .mockReturnValueOnce(newTasks.promise);
      wrapper = shallowMount(ProjectDetail, {
        global: { stubs: { KeepAlive: false, RouterLink: true } },
      });
      request.mockResolvedValue({
        data: { ...project, id: 8, name: 'Current project' },
      });
      if (identity === 'project') route.params.projectId = '8';
      else accountId.value = 2;
      await flushPromises();
      expect(wrapper.get('h1').text()).toBe('Current project');
      oldProject.resolve({ data: project });
      oldTasks.resolve(tasks);
      await flushPromises();
      expect(wrapper.get('h1').text()).toBe('Current project');
      expect(wrapper.findComponent(ProjectExecution).props('tasks')).toEqual(
        []
      );
      expect(wrapper.get('[role="tabpanel"]').attributes('aria-busy')).toBe(
        'true'
      );
      newTasks.resolve([{ id: 81, title: 'Current task' }]);
      await flushPromises();
      expect(wrapper.findComponent(ProjectExecution).props('tasks')).toEqual([
        { id: 81, title: 'Current task' },
      ]);
    }
  );

  it('never reveals tasks before the project read authorizes its identity', async () => {
    const pending = deferred();
    request.mockReturnValue(pending.promise);
    wrapper = shallowMount(ProjectDetail, {
      global: { stubs: { KeepAlive: false, RouterLink: true } },
    });
    await flushPromises();
    expect(wrapper.find('h1').exists()).toBe(false);
    expect(wrapper.findComponent(ProjectExecution).exists()).toBe(false);
    pending.reject(new Error('Forbidden'));
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('Forbidden');
    expect(wrapper.find('h1').exists()).toBe(false);
  });

  it.each(['project', 'account'])(
    'clears visible identity immediately during a %s change',
    async identity => {
      const oldTasks = deferred();
      const nextProject = deferred();
      allPages.mockReturnValueOnce(oldTasks.promise);
      wrapper = shallowMount(ProjectDetail, {
        global: { stubs: { KeepAlive: false, RouterLink: true } },
      });
      await flushPromises();
      expect(wrapper.get('h1').text()).toBe('Authorized project');
      request.mockReturnValue(nextProject.promise);
      if (identity === 'project') route.params.projectId = '8';
      else accountId.value = 2;
      await flushPromises();
      expect(wrapper.find('h1').exists()).toBe(false);
      oldTasks.resolve(tasks);
      await flushPromises();
      expect(wrapper.findComponent(ProjectExecution).exists()).toBe(false);
      nextProject.resolve({ data: { ...project, name: 'Current project' } });
      await flushPromises();
      expect(wrapper.get('h1').text()).toBe('Current project');
    }
  );

  it('clears previously authorized content if a project refresh is denied', async () => {
    wrapper = shallowMount(ProjectDetail, {
      global: { stubs: { KeepAlive: false, RouterLink: true } },
    });
    await flushPromises();
    request.mockRejectedValue(new Error('Forbidden'));
    await expect(
      wrapper.findComponent(ProjectExecution).props('refresh')()
    ).rejects.toThrow('Forbidden');
    await flushPromises();
    expect(wrapper.find('h1').exists()).toBe(false);
    expect(wrapper.findComponent(ProjectExecution).exists()).toBe(false);
    expect(wrapper.get('[role="alert"]').text()).toContain('Forbidden');
  });

  it('does not publish a late project after its task read was denied', async () => {
    const pending = deferred();
    request.mockReturnValue(pending.promise);
    allPages.mockRejectedValue(new Error('Forbidden'));
    wrapper = shallowMount(ProjectDetail, {
      global: { stubs: { KeepAlive: false, RouterLink: true } },
    });
    await flushPromises();
    pending.resolve({ data: project });
    await flushPromises();
    expect(wrapper.find('h1').exists()).toBe(false);
    expect(wrapper.get('[role="alert"]').text()).toContain('Forbidden');
  });
});
