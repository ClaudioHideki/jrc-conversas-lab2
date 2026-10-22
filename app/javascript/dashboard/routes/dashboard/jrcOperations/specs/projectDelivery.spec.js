import { effectScope, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import {
  taskProgress,
  useProjectPreferences,
} from '../../jrcProjects/projectPresentation';
import ProjectHours from '../components/ProjectHours.vue';
import FilesBox from '../components/FilesBox.vue';
import { request, allPages } from '../api';

vi.mock('../../jrcProjects/useProjects', () => ({
  useProjects: () => ({
    accountId: ref(1),
    projectText: (key, fallback) => fallback,
  }),
}));
vi.mock('../api', async importOriginal => ({
  ...(await importOriginal()),
  request: vi.fn(),
  allPages: vi.fn(),
}));

describe('Project delivery integration', () => {
  beforeEach(() => {
    localStorage.clear();
    allPages.mockResolvedValue([]);
    request.mockResolvedValue({ data: [] });
  });

  it('loads pages sequentially and preserves their order and account scope', async () => {
    const actual = await vi.importActual('../api');
    const previous = window.axios;
    window.axios = vi
      .fn()
      .mockResolvedValueOnce({
        data: { data: [{ id: 1 }], meta: { total: 2 } },
      })
      .mockResolvedValueOnce({
        data: { data: [{ id: 2 }], meta: { total: 2 } },
      });
    try {
      expect(await actual.allPages(3, 'projects/projects/7/tasks')).toEqual([
        { id: 1 },
        { id: 2 },
      ]);
      expect(
        window.axios.mock.calls.map(([options]) => options.params.page)
      ).toEqual([1, 2]);
      expect(
        window.axios.mock.calls.every(
          ([options]) =>
            options.url === '/api/v1/accounts/3/projects/projects/7/tasks'
        )
      ).toBe(true);
    } finally {
      window.axios = previous;
    }
  });

  it('rejects excessive totals and stops at the existing 100-page bound', async () => {
    const actual = await vi.importActual('../api');
    const previous = window.axios;
    window.axios = vi.fn().mockResolvedValue({
      data: { data: [{ id: 1 }], meta: { total: 10001 } },
    });
    try {
      await expect(actual.allPages(1, 'projects/projects')).rejects.toThrow(
        'Mais de 10 mil'
      );
      expect(window.axios).toHaveBeenCalledTimes(1);
      window.axios.mockClear().mockResolvedValue({
        data: { data: [{ id: 1 }], meta: { total: 101 } },
      });
      await expect(actual.allPages(1, 'projects/projects')).rejects.toThrow(
        'Limite de paginacao'
      );
      expect(window.axios).toHaveBeenCalledTimes(100);
    } finally {
      window.axios = previous;
    }
  });

  it('keeps execution preferences isolated when changing account, user and project', () => {
    const scope = effectScope();
    const key = ref('projects:1:10:100');
    const filters = scope.run(() =>
      useProjectPreferences(key, { q: '', status: '' })
    );
    filters.q = 'private filter';
    key.value = 'projects:2:20:200';
    expect(filters.q).toBe('');
    filters.status = 'completed';
    key.value = 'projects:1:10:100';
    expect(filters.q).toBe('private filter');
    expect(filters.status).toBe('');
    scope.stop();
  });

  it('does not invent checklist completion from the task status', () => {
    expect(
      taskProgress({
        status: 'completed',
        checklist_total: 2,
        checklist_completed: 1,
      })
    ).toBe(50);
    expect(taskProgress({ status: 'completed', checklist_total: 0 })).toBe(0);
  });

  it('does not request budgets or display financial controls without the capability', async () => {
    const wrapper = mount(ProjectHours, {
      props: { project: { id: 7, status: 'active', capabilities: [] } },
    });
    await flushPromises();
    expect(allPages).toHaveBeenCalledWith(
      1,
      'projects/projects/7/time_entries'
    );
    expect(request).not.toHaveBeenCalled();
    expect(wrapper.find('input[type="number"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('submits HH:MM as minutes to the current project without a financial write', async () => {
    const wrapper = mount(ProjectHours, {
      props: {
        project: {
          id: 7,
          status: 'active',
          capabilities: ['projects.time_entry.create'],
        },
      },
    });
    await flushPromises();
    await wrapper.find('form input[type="text"]').setValue('01:30');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(request).toHaveBeenCalledWith(
      1,
      'projects/projects/7/time_entries',
      expect.objectContaining({
        method: 'post',
        data: {
          time_entry: expect.objectContaining({ minutes: 90, task_id: null }),
        },
      })
    );
    wrapper.unmount();
  });

  it('loads attachments through the supplied project or shared resource endpoint without writing', async () => {
    const wrapper = mount(FilesBox, {
      props: { endpoint: 'projects/projects/7/attachments', canEdit: false },
    });
    await flushPromises();
    expect(request).toHaveBeenCalledWith(1, 'projects/projects/7/attachments');
    expect(wrapper.find('input[type="file"]').exists()).toBe(false);
    await wrapper.setProps({ endpoint: 'service_desk/tickets/8/attachments' });
    await flushPromises();
    expect(request).toHaveBeenLastCalledWith(
      1,
      'service_desk/tickets/8/attachments'
    );
    expect(request.mock.calls.every(call => call.length === 2)).toBe(true);
    wrapper.unmount();
  });
});
