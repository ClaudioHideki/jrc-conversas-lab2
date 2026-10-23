import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import DeleteProjectButton from '../../jrcProjects/components/DeleteProjectButton.vue';
import ProjectExecution from '../../jrcProjects/components/ProjectExecution.vue';
import TaskEditor from '../components/TaskEditor.vue';
import ProjectHours from '../components/ProjectHours.vue';
import OpsModal from '../components/OpsModal.vue';
import en from '../../jrcProjects/en.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/jrcProjects.json';
import { request, allPages } from '../api';

vi.mock('../../jrcProjects/useProjects', () => ({
  useProjects: () => ({
    accountId: ref(1),
    userId: ref(10),
    projectText: (key, fallback) => pt_BR[key] || fallback,
  }),
}));
vi.mock('../api', async importOriginal => ({
  ...(await importOriginal()),
  request: vi.fn(),
  allPages: vi.fn(),
}));

const project = {
  id: 7,
  key: 'PR-7',
  name: 'Implantação',
  status: 'active',
  lock_version: 4,
  capabilities: ['projects.project.delete', 'projects.task.update'],
  members: [],
  columns: [{ id: 1, name: 'A fazer', status_key: 'backlog' }],
};
const task = {
  id: 20,
  title: 'Configurar atendimento',
  priority: 'medium',
  status: 'backlog',
  board_column_id: 1,
  lock_version: 3,
  can_update: true,
  can_delete: true,
  comments: [],
  checklist: [],
};
const modalStub = { template: '<section><slot /></section>' };

describe('Edição, exclusão e idioma dos projetos', () => {
  beforeEach(() => {
    request.mockReset().mockResolvedValue({ data: task });
    allPages.mockReset().mockResolvedValue([]);
    vi.spyOn(window, 'confirm').mockReturnValue(true);
  });
  afterEach(() => vi.restoreAllMocks());

  it('covers every catalog key in Portuguese, including the new dashboard and modal controls', () => {
    expect(Object.keys(pt_BR).sort()).toEqual(Object.keys(en).sort());
    expect(pt_BR.EXECUTION).toBe('Execução');
    expect(pt_BR.PLANNING).toBe('Planejamento');
    expect(pt_BR.EXPORT_TASKS).toBe('Exportar tarefas');
    expect(pt_BR.CLOSE_WINDOW).toBe('Fechar janela');
    expect(Object.values(pt_BR).every(value => value.trim().length > 0)).toBe(
      true
    );
  });

  it('loads Portuguese for the real modal instead of its English-only catalog', async () => {
    const wrapper = mount(OpsModal, {
      props: { title: 'Tarefa', drawer: true },
      global: {
        plugins: [createI18n({ legacy: false, locale: 'pt_BR' })],
        stubs: { teleport: true },
      },
    });
    expect(wrapper.find('[aria-label="Fechar janela"]').text()).toBe('Fechar');
    expect(wrapper.find('[aria-label="Expandir painel"]').exists()).toBe(true);
    await wrapper.find('[aria-label="Expandir painel"]').trigger('click');
    expect(wrapper.find('[aria-label="Recolher painel"]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('does not expose deletion without the project capability', () => {
    const wrapper = mount(DeleteProjectButton, {
      props: { project: { ...project, capabilities: [] } },
    });
    expect(wrapper.find('button').exists()).toBe(false);
    expect(request).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('canceling the confirmation leaves the project untouched', async () => {
    window.confirm.mockReturnValue(false);
    const wrapper = mount(DeleteProjectButton, { props: { project } });
    await wrapper.find('button').trigger('click');
    expect(request).not.toHaveBeenCalled();
    expect(wrapper.emitted('deleted')).toBeUndefined();
    wrapper.unmount();
  });

  it('deletes the selected project with its version only after the server accepts', async () => {
    const wrapper = mount(DeleteProjectButton, { props: { project } });
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(request).toHaveBeenCalledWith(1, 'projects/projects/7', {
      method: 'delete',
      data: { lock_version: 4 },
    });
    expect(wrapper.emitted('deleted')).toEqual([[project]]);
    wrapper.unmount();
  });

  it('reports server refusal without emitting a successful deletion', async () => {
    request.mockRejectedValue(new Error('Projeto com horas aprovadas.'));
    const wrapper = mount(DeleteProjectButton, { props: { project } });
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.emitted('error')).toEqual([
      ['Projeto com horas aprovadas.'],
    ]);
    expect(wrapper.emitted('deleted')).toBeUndefined();
    expect(wrapper.find('button').attributes('disabled')).toBeUndefined();
    wrapper.unmount();
  });

  it('deletes a task through its actual endpoint and closes only on success', async () => {
    const wrapper = mount(TaskEditor, {
      props: { project, task },
      global: { stubs: { OpsModal: modalStub } },
    });
    await flushPromises();
    const button = wrapper
      .findAll('button')
      .find(item => item.text() === 'Excluir tarefa');
    await button.trigger('click');
    await flushPromises();
    expect(request).toHaveBeenLastCalledWith(
      1,
      'projects/projects/7/tasks/20',
      {
        method: 'delete',
        data: { lock_version: 3 },
      }
    );
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(wrapper.emitted('changed')).toHaveLength(1);
    wrapper.unmount();
  });

  it('preserves the task editor when its deletion is rejected', async () => {
    const wrapper = mount(TaskEditor, {
      props: { project, task },
      global: { stubs: { OpsModal: modalStub } },
    });
    await flushPromises();
    request.mockRejectedValue(
      new Error('Remova os vínculos antes de excluir.')
    );
    await wrapper
      .findAll('button')
      .find(item => item.text() === 'Excluir tarefa')
      .trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'Remova os vínculos'
    );
    expect(wrapper.emitted('close')).toBeUndefined();
    wrapper.unmount();
  });

  it('edits a checklist item through PATCH and reloads its persisted value', async () => {
    request.mockResolvedValue({
      data: {
        ...task,
        checklist: [{ id: 5, text: 'Original', completed: false }],
      },
    });
    const wrapper = mount(TaskEditor, {
      props: { project, task },
      global: { stubs: { OpsModal: modalStub } },
    });
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(item => item.text() === 'Checklist')
      .trigger('click');
    await wrapper
      .findAll('button')
      .find(item => item.text() === 'Editar')
      .trigger('click');
    await wrapper
      .find('input[aria-label="Texto do item"]')
      .setValue('Verificar tronco SIP');
    await wrapper
      .find('input[aria-label="Texto do item"]')
      .element.closest('form')
      .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await flushPromises();
    expect(request).toHaveBeenCalledWith(
      1,
      'projects/projects/7/tasks/20/checklist_items/5',
      {
        method: 'patch',
        data: { item: { text: 'Verificar tronco SIP' } },
      }
    );
    expect(request).toHaveBeenLastCalledWith(1, 'projects/projects/7/tasks/20');
    wrapper.unmount();
  });

  it('only offers author comment controls to that author or a manager', async () => {
    request.mockResolvedValue({
      data: {
        ...task,
        comments: [
          { id: 8, user_id: 10, body: 'Minha nota' },
          { id: 9, user_id: 11, body: 'Outra pessoa' },
        ],
      },
    });
    const wrapper = mount(TaskEditor, {
      props: { project, task },
      global: { stubs: { OpsModal: modalStub } },
    });
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(item => item.text() === 'Comentários')
      .trigger('click');
    const entries = wrapper.findAll('article');
    expect(entries[0].findAll('button')).toHaveLength(2);
    expect(entries[1].findAll('button')).toHaveLength(0);
    await entries[0].findAll('button')[0].trigger('click');
    await entries[0].find('textarea').setValue('Nota revisada');
    await entries[0].find('form').trigger('submit');
    await flushPromises();
    expect(request).toHaveBeenCalledWith(
      1,
      'projects/projects/7/tasks/20/comments/8',
      {
        method: 'patch',
        data: { comment: { body: 'Nota revisada' } },
      }
    );
    wrapper.unmount();
  });

  it('edits an existing time entry instead of adding another entry', async () => {
    allPages.mockResolvedValue([
      {
        id: 8,
        user_id: 10,
        user: { id: 10, name: 'Agente' },
        status: 'submitted',
        worked_on: '2026-10-23',
        minutes: 60,
        notes: 'Original',
        can_update: true,
        can_delete: true,
      },
    ]);
    const wrapper = mount(ProjectHours, {
      props: {
        project: { ...project, capabilities: ['projects.time_entry.create'] },
      },
    });
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(item => item.text() === 'Editar')
      .trigger('click');
    await wrapper.find('form input[type="text"]').setValue('01:30');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(request).toHaveBeenCalledWith(
      1,
      'projects/projects/7/time_entries/8',
      expect.objectContaining({
        method: 'patch',
        data: { time_entry: expect.objectContaining({ minutes: 90 }) },
      })
    );
    expect(
      request.mock.calls.some(([, , options]) => options?.method === 'post')
    ).toBe(false);
    wrapper.unmount();
  });

  it('uses the server delete permission for time entries', async () => {
    allPages.mockResolvedValue([
      {
        id: 8,
        user_id: 10,
        status: 'approved',
        worked_on: '2026-10-23',
        minutes: 60,
        can_update: true,
        can_delete: false,
      },
    ]);
    const wrapper = mount(ProjectHours, { props: { project } });
    await flushPromises();
    expect(
      wrapper.findAll('button').some(item => item.text() === 'Excluir')
    ).toBe(false);
    wrapper.unmount();
  });

  it('removes a task from the Kanban through the API and refreshes the persisted board', async () => {
    const refresh = vi.fn().mockResolvedValue();
    const wrapper = mount(ProjectExecution, {
      props: {
        project,
        tasks: [task],
        filters: { boardView: 'board' },
        synced: true,
        refresh,
      },
    });
    await wrapper
      .findAll('button')
      .find(item => item.text() === 'Excluir')
      .trigger('click');
    await flushPromises();
    expect(request).toHaveBeenCalledWith(1, 'projects/projects/7/tasks/20', {
      method: 'delete',
      data: { lock_version: 3 },
    });
    expect(refresh).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });

  it('keeps a failed Kanban deletion visible and shows the server error', async () => {
    request.mockRejectedValue(new Error('Tarefa vinculada a um chamado.'));
    const refresh = vi.fn().mockResolvedValue();
    const wrapper = mount(ProjectExecution, {
      props: {
        project,
        tasks: [task],
        filters: { boardView: 'board' },
        synced: true,
        refresh,
      },
    });
    await wrapper
      .findAll('button')
      .find(item => item.text() === 'Excluir')
      .trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Tarefa vinculada a um chamado.');
    expect(wrapper.text()).toContain(task.title);
    expect(refresh).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });
});
