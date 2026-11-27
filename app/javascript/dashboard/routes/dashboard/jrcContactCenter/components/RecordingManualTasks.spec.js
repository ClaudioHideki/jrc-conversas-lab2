import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import RecordingManualTasks from './RecordingManualTasks.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { recordingTasks: vi.fn(), createRecordingTask: vi.fn() },
}));
enableAutoUnmount(afterEach);
beforeEach(() => vi.resetAllMocks());
const key = '11111111-1111-4111-8111-111111111111';
const row = number => ({
  id: String(number),
  account_user_id: '4',
  created_at: '2026-11-27T12:00:00Z',
  request_id: key,
  target: { kind: 'project_task', project_id: '9', id: String(number + 100) },
});
const body = (items = [row(1)], page = 1, total = items.length) => ({
  contract_version: 1,
  account_id: '1',
  recording_id: '5',
  call_session_id: '7',
  call_id: 'SYNTHETIC-call',
  project_module_available: true,
  timezone: 'America/Sao_Paulo',
  items,
  meta: { page, per_page: 20, total, pages: Math.ceil(total / 20) },
});
const render = () =>
  mount(RecordingManualTasks, {
    props: {
      accountId: '1',
      recordingId: '5',
      callSessionId: '7',
      callId: 'SYNTHETIC-call',
      authorityKey: 'current-profile',
    },
    global: {
      stubs: {
        EndingTaskState: true,
        RouterLink: { props: ['to'], template: '<a><slot /></a>' },
      },
    },
  });
const button = (wrapper, suffix) =>
  wrapper.findAll('button').find(item => item.text().endsWith(suffix));

describe('native manual task links in recording Actions', () => {
  it('reads current native links without writing and opts in only the authorized native task-state reader', async () => {
    API.recordingTasks.mockResolvedValue({ data: body() });
    const wrapper = render();
    await flushPromises();
    expect(API.recordingTasks).toHaveBeenCalledTimes(1);
    expect(API.recordingTasks).toHaveBeenCalledWith('1', '5', 1);
    expect(API.createRecordingTask).not.toHaveBeenCalled();
    expect(
      wrapper.getComponent({ name: 'EndingTaskState' }).props('loadOnOpen')
    ).toBe(true);
    expect(wrapper.findAll('[data-recording-manual-task-row]')).toHaveLength(1);
    expect(wrapper.get('time').text()).toContain('09:00');
    expect(
      wrapper.getComponent({ name: 'EndingTaskState' }).props()
    ).toMatchObject({
      accountId: '1',
      projectId: '9',
      taskId: '101',
      authorityKey: 'current-profile',
    });
    await wrapper.get('[data-recording-new-task]').trigger('click');
    expect(wrapper.emitted('create')).toHaveLength(1);
  });

  it('preserves a historical link while hiding a newly private target and its actions', async () => {
    API.recordingTasks.mockResolvedValue({
      data: body([{ ...row(1), target: null }]),
    });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.find('[data-recording-manual-task-row]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-open-recording-manual-task]').exists()).toBe(
      false
    );
    expect(wrapper.findComponent({ name: 'EndingTaskState' }).exists()).toBe(
      false
    );
    expect(wrapper.text()).toContain('TARGET_UNAVAILABLE');
  });

  it('does not offer task creation when the native destination module is unavailable', async () => {
    API.recordingTasks.mockResolvedValue({
      data: { ...body([]), project_module_available: false },
    });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.find('[data-recording-new-task]').exists()).toBe(false);
    expect(wrapper.text()).toContain('NO_MODULE');
    expect(API.createRecordingTask).not.toHaveBeenCalled();
  });

  it('navigates all 21 actual links in two pages and returns to page one', async () => {
    const first = body(
      Array.from({ length: 20 }, (_, i) => row(i + 1)),
      1,
      21
    );
    API.recordingTasks
      .mockResolvedValueOnce({ data: first })
      .mockResolvedValueOnce({ data: body([row(21)], 2, 21) })
      .mockResolvedValueOnce({ data: first });
    const wrapper = render();
    await flushPromises();
    await button(wrapper, '.NEXT').trigger('click');
    await flushPromises();
    expect(API.recordingTasks).toHaveBeenLastCalledWith('1', '5', 2);
    expect(wrapper.findAll('[data-recording-manual-task-row]')).toHaveLength(1);
    await button(wrapper, '.PREVIOUS').trigger('click');
    await flushPromises();
    expect(API.recordingTasks).toHaveBeenLastCalledWith('1', '5', 1);
    expect(wrapper.findAll('[data-recording-manual-task-row]')).toHaveLength(
      20
    );
  });

  it.each([401, 403, 404])(
    'clears prior links and blocks stale controls after native denial %s',
    async status => {
      API.recordingTasks.mockResolvedValueOnce({ data: body() });
      const wrapper = render();
      await flushPromises();
      API.recordingTasks.mockRejectedValueOnce({ response: { status } });
      await button(wrapper, '.REFRESH').trigger('click');
      await flushPromises();
      expect(wrapper.findAll('[data-recording-manual-task-row]')).toHaveLength(
        0
      );
      expect(wrapper.find('[data-recording-new-task]').exists()).toBe(false);
      expect(wrapper.text()).toContain('DENIED');
      expect(button(wrapper, '.REFRESH').attributes('disabled')).toBeDefined();
    }
  );

  it('drops delayed data after a profile switch without issuing another read or any write automatically', async () => {
    let resolve;
    API.recordingTasks.mockReturnValueOnce(
      new Promise(done => {
        resolve = done;
      })
    );
    const wrapper = render();
    await wrapper.setProps({ authorityKey: 'restricted-profile' });
    resolve({ data: body() });
    await flushPromises();
    expect(wrapper.findAll('[data-recording-manual-task-row]')).toHaveLength(0);
    expect(wrapper.find('[data-recording-new-task]').exists()).toBe(false);
    expect(API.recordingTasks).toHaveBeenCalledTimes(1);
    expect(API.createRecordingTask).not.toHaveBeenCalled();
  });

  it('refreshes after a confirmed creation and does not repeat the creation command itself', async () => {
    API.recordingTasks
      .mockResolvedValueOnce({ data: body([]) })
      .mockResolvedValueOnce({ data: body() });
    const wrapper = render();
    await flushPromises();
    await wrapper.setProps({ revision: 1 });
    await flushPromises();
    expect(wrapper.findAll('[data-recording-manual-task-row]')).toHaveLength(1);
    expect(API.recordingTasks).toHaveBeenCalledTimes(2);
    expect(API.createRecordingTask).not.toHaveBeenCalled();
  });

  it.each(['account', 'duplicate', 'timezone', 'key'])(
    'rejects a malformed native link page: %s',
    async kind => {
      const invalid = body();
      if (kind === 'account') invalid.account_id = '99';
      if (kind === 'duplicate') {
        invalid.items = [row(1), row(1)];
        invalid.meta = { page: 1, per_page: 20, total: 2, pages: 1 };
      }
      if (kind === 'timezone') invalid.timezone = 'Invalid/Synthetic';
      if (kind === 'key') invalid.items[0].request_id = null;
      API.recordingTasks.mockResolvedValue({ data: invalid });
      const wrapper = render();
      await flushPromises();
      expect(wrapper.findAll('[data-recording-manual-task-row]')).toHaveLength(
        0
      );
      expect(wrapper.text()).toContain('ERROR');
    }
  );

  it('retains an explicit recoverable error after network failure without an automatic retry', async () => {
    API.recordingTasks.mockRejectedValueOnce(new Error('offline'));
    const wrapper = render();
    await flushPromises();
    expect(wrapper.text()).toContain('ERROR');
    expect(API.recordingTasks).toHaveBeenCalledTimes(1);
    API.recordingTasks.mockResolvedValueOnce({ data: body() });
    await button(wrapper, '.REFRESH').trigger('click');
    await flushPromises();
    expect(wrapper.findAll('[data-recording-manual-task-row]')).toHaveLength(1);
  });
});
