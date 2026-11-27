import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { request } from '../../jrcOperations/api';
import RecordingTaskCreate from './RecordingTaskCreate.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { createRecordingTask: vi.fn() },
}));
vi.mock('../../jrcOperations/api', () => ({ request: vi.fn() }));
enableAutoUnmount(afterEach);
const key = '11111111-1111-4111-8111-111111111111';
const project = changes => ({
  id: 9,
  name: 'SYNTHETIC permitted private project',
  status: 'active',
  capabilities: ['projects.task.create'],
  columns: [],
  members: [],
  ...changes,
});
const receipt = () => ({
  data: { account_id: '1', recording_id: '5', link_id: '12' },
});
const render = () =>
  mount(RecordingTaskCreate, {
    props: { accountId: '1', recordingId: '5', authorityKey: 'profile-A' },
    global: {
      stubs: {
        OpsModal: { template: '<section><slot /></section>' },
        TaskEditor: {
          name: 'TaskEditor',
          props: ['project', 'createRequest'],
          template: '<form data-native-task-editor-stub />',
        },
      },
    },
  });
const choose = async wrapper => {
  await flushPromises();
  await wrapper.get('[data-create-task-project="9"]').trigger('click');
  await flushPromises();
};
const callback = wrapper =>
  wrapper.getComponent({ name: 'TaskEditor' }).props('createRequest');
beforeEach(() => {
  vi.resetAllMocks();
  vi.stubGlobal('crypto', { randomUUID: vi.fn(() => key) });
  request.mockImplementation((_account, path) =>
    Promise.resolve(
      path.endsWith('/9')
        ? { data: project() }
        : { data: [project()], meta: { total: 1 } }
    )
  );
  API.createRecordingTask.mockResolvedValue(receipt());
});
afterEach(() => vi.unstubAllGlobals());

describe('explicit recording task creation through the existing native editor', () => {
  it('queries only authorized native Projects and hands current columns, members and create callback to the native Task editor', async () => {
    const wrapper = render();
    await choose(wrapper);
    expect(request).toHaveBeenCalledWith('1', 'projects/projects', {
      params: { q: '', page: 1, per_page: 20 },
    });
    expect(request).toHaveBeenCalledWith('1', 'projects/projects/9');
    expect(
      wrapper.getComponent({ name: 'TaskEditor' }).props('project')
    ).toEqual(project());
    expect(API.createRecordingTask).not.toHaveBeenCalled();
    await callback(wrapper)({
      task: { title: 'SYNTHETIC authored title', lock_version: undefined },
    });
    expect(API.createRecordingTask).toHaveBeenCalledTimes(1);
    expect(API.createRecordingTask).toHaveBeenCalledWith('1', '5', {
      project_id: '9',
      request_id: key,
      task: { title: 'SYNTHETIC authored title' },
    });
  });

  it.each(['missing-capability', 'closed'])(
    'does not let the project picker confer permission for %s',
    async kind => {
      const unavailable = project(
        kind === 'closed' ? { status: 'completed' } : { capabilities: [] }
      );
      request.mockResolvedValue({ data: [unavailable], meta: { total: 1 } });
      const wrapper = render();
      await flushPromises();
      expect(
        wrapper.get('[data-create-task-project="9"]').attributes('disabled')
      ).toBeDefined();
      expect(wrapper.find('[data-native-task-editor-stub]').exists()).toBe(
        false
      );
      expect(API.createRecordingTask).not.toHaveBeenCalled();
    }
  );

  it('rechecks native project details before mounting the editor when permission was withdrawn after the list read', async () => {
    request
      .mockResolvedValueOnce({ data: [project()], meta: { total: 1 } })
      .mockRejectedValueOnce({ response: { status: 403 } });
    const wrapper = render();
    await choose(wrapper);
    expect(wrapper.find('[data-native-task-editor-stub]').exists()).toBe(false);
    expect(wrapper.text()).toContain('DENIED');
    expect(API.createRecordingTask).not.toHaveBeenCalled();
  });

  it('retains one request UUID and the exact body after an uncertain network result and blocks an edited automatic retry', async () => {
    const wrapper = render();
    await choose(wrapper);
    API.createRecordingTask.mockRejectedValueOnce(new Error('connection lost'));
    const createTask = callback(wrapper);
    const payload = { task: { title: 'SYNTHETIC original draft' } };
    await expect(createTask(payload)).rejects.toThrow('UNKNOWN');
    expect(API.createRecordingTask).toHaveBeenCalledTimes(1);
    await expect(
      createTask({ task: { title: 'SYNTHETIC altered draft' } })
    ).rejects.toThrow('UNKNOWN');
    expect(API.createRecordingTask).toHaveBeenCalledTimes(1);
    await expect(createTask(payload)).resolves.toBeUndefined();
    expect(API.createRecordingTask).toHaveBeenCalledTimes(2);
    expect(API.createRecordingTask.mock.calls[1]).toEqual(
      API.createRecordingTask.mock.calls[0]
    );
  });

  it('preserves an invalid draft for correction after an explicit native validation refusal without an automatic POST', async () => {
    const wrapper = render();
    await choose(wrapper);
    const failure = {
      response: { status: 422, data: { error: 'SYNTHETIC native validation' } },
    };
    API.createRecordingTask.mockRejectedValueOnce(failure);
    const createTask = callback(wrapper);
    await expect(createTask({ task: { title: '' } })).rejects.toBe(failure);
    expect(API.createRecordingTask).toHaveBeenCalledTimes(1);
    await expect(
      createTask({ task: { title: 'SYNTHETIC corrected title' } })
    ).resolves.toBeUndefined();
    expect(API.createRecordingTask).toHaveBeenCalledTimes(2);
    expect(
      API.createRecordingTask.mock.calls.map(args => args[2].request_id)
    ).toEqual([key, key]);
  });

  it('rejects a receipt from another account without showing success or changing its request UUID', async () => {
    API.createRecordingTask.mockResolvedValueOnce({
      data: { account_id: '99', recording_id: '5', link_id: '12' },
    });
    const wrapper = render();
    await choose(wrapper);
    await expect(
      callback(wrapper)({ task: { title: 'SYNTHETIC draft' } })
    ).rejects.toThrow('UNKNOWN');
    expect(wrapper.emitted('changed')).toBeUndefined();
    expect(wrapper.emitted('close')).toBeUndefined();
    expect(API.createRecordingTask).toHaveBeenCalledTimes(1);
  });

  it('closes and forgets a pending project response when the current source or profile changes', async () => {
    let resolve;
    request.mockReturnValueOnce(
      new Promise(done => {
        resolve = done;
      })
    );
    const wrapper = render();
    await wrapper.setProps({ authorityKey: 'profile-B' });
    resolve({ data: [project()], meta: { total: 1 } });
    await flushPromises();
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(wrapper.find('[data-create-task-project="9"]').exists()).toBe(false);
    expect(wrapper.find('[data-native-task-editor-stub]').exists()).toBe(false);
    expect(API.createRecordingTask).not.toHaveBeenCalled();
  });
  it('preserves the native editor without success or an automatic retry when current create permission is withdrawn during editing', async () => {
    const wrapper = render();
    await choose(wrapper);
    API.createRecordingTask.mockRejectedValueOnce({
      response: { status: 403 },
    });
    await expect(
      callback(wrapper)({ task: { title: 'SYNTHETIC preserved draft' } })
    ).rejects.toThrow('DENIED');
    expect(API.createRecordingTask).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-native-task-editor-stub]').exists()).toBe(true);
    expect(wrapper.emitted('changed')).toBeUndefined();
    expect(wrapper.emitted('close')).toBeUndefined();
  });
});
