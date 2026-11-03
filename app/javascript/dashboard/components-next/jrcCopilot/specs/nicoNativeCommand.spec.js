/* global axios */
import { runNicoModuleAction } from '../nicoModuleActions';

describe('NICO native task execution context', () => {
  const action = {
    browser_action: 'module_action_fenced',
    operation: 'update_project_task',
    parameters: {
      project_id: 12,
      task_id: 42,
      lock_version: 0,
      title: 'Reviewed',
    },
    native_execution: { command_id: 19, contract: 'nico-native-v1' },
  };
  beforeEach(() => {
    global.axios = { patch: vi.fn().mockResolvedValue({ data: { id: 42 } }) };
  });
  afterEach(() => delete global.axios);

  it('sends the claimed command with the exact native task request', async () => {
    await runNicoModuleAction(7, action);
    expect(axios.patch).toHaveBeenCalledExactlyOnceWith(
      '/api/v1/accounts/7/projects/projects/12/tasks/42',
      { task: { lock_version: 0, title: 'Reviewed' } },
      {
        headers: {
          'X-JRC-Nico-Command-Id': '19',
          'X-JRC-Nico-Contract': 'nico-native-v1',
        },
      }
    );
  });

  it('refuses to silently downgrade a task command to a human request', async () => {
    await expect(
      runNicoModuleAction(7, { ...action, native_execution: null })
    ).rejects.toThrow('comando');
    expect(axios.patch).not.toHaveBeenCalled();
  });

  it('refuses unsupported execution context versions before any request', async () => {
    await expect(
      runNicoModuleAction(7, {
        ...action,
        native_execution: { command_id: 19, contract: 'nico-native-v2' },
      })
    ).rejects.toThrow('comando');
    expect(axios.patch).not.toHaveBeenCalled();
  });
});
