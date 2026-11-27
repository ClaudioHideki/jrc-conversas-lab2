import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import EndingTaskState from './EndingTaskState.vue';
import { request } from '../jrcOperations/api';

vi.mock('../jrcOperations/api', async importOriginal => ({
  ...(await importOriginal()),
  request: vi.fn(),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
enableAutoUnmount(afterEach);
const task = () => ({
  id: 15,
  project_id: 9,
  status: 'in_progress',
  assignee_id: 4,
  assignee: { id: 4, name: 'SYNTHETIC current owner' },
  due_on: '2026-11-30',
  title: 'SYNTHETIC undisplayed title',
  description: 'SYNTHETIC undisplayed details',
  comments: ['SYNTHETIC undisplayed comment'],
});
const create = () =>
  mount(EndingTaskState, {
    props: {
      accountId: '1',
      projectId: '9',
      taskId: '15',
      authorityKey: 'profile-1',
    },
  });
const load = async wrapper => {
  await wrapper.get('[data-load-native-task-state]').trigger('click');
  await flushPromises();
};
beforeEach(() => {
  request.mockReset();
  request.mockResolvedValue({ data: task() });
});

describe('current native Project task state alongside immutable call receipts', () => {
  it('loads only on explicit request through the existing scoped native task GET', async () => {
    const wrapper = create();
    expect(request).not.toHaveBeenCalled();
    await load(wrapper);
    expect(request).toHaveBeenCalledTimes(1);
    expect(request).toHaveBeenCalledWith('1', 'projects/projects/9/tasks/15', {
      signal: expect.any(AbortSignal),
    });
    expect(wrapper.get('[data-native-task-status]').text()).toBe(
      'Em andamento'
    );
    expect(wrapper.get('[data-native-task-assignee]').text()).toBe(
      'SYNTHETIC current owner'
    );
    expect(wrapper.get('time').attributes('datetime')).toBe('2026-11-30');
    expect(wrapper.get('[data-native-task-due]').text()).toBe('30/11/2026');
  });

  it('does not render or store native comments, descriptions or editable task controls', async () => {
    const wrapper = create();
    await load(wrapper);
    expect(wrapper.text()).not.toContain('undisplayed');
    expect(wrapper.find('input, textarea, form').exists()).toBe(false);
    expect(wrapper.findAll('button')).toHaveLength(1);
  });

  it('refreshes actual changed state, owner and deadline without issuing a write', async () => {
    const wrapper = create();
    await load(wrapper);
    request.mockResolvedValueOnce({
      data: {
        ...task(),
        status: 'blocked',
        assignee_id: null,
        assignee: null,
        due_on: null,
      },
    });
    await load(wrapper);
    expect(wrapper.get('[data-native-task-status]').text()).toBe('Bloqueado');
    expect(wrapper.get('[data-native-task-assignee]').text()).toContain(
      'UNASSIGNED'
    );
    expect(wrapper.get('[data-native-task-due]').text()).toContain('NO_DUE');
    expect(request).toHaveBeenCalledTimes(2);
    expect(
      request.mock.calls.every(args => !args[2].method && !args[2].data)
    ).toBe(true);
  });

  it.each([401, 403, 404])(
    'clears previous details on current native denial %s, without fabricating completed task status',
    async status => {
      const wrapper = create();
      await load(wrapper);
      request.mockRejectedValueOnce({ response: { status } });
      await load(wrapper);
      expect(wrapper.get('[role="alert"]').text()).toContain('DENIED');
      expect(wrapper.find('[data-native-task-status]').exists()).toBe(false);
      expect(wrapper.text()).not.toContain('SYNTHETIC current owner');
      expect(
        wrapper.get('[data-load-native-task-state]').attributes('disabled')
      ).toBeDefined();
    }
  );

  it('immediately clears details when profile or task changes and requests the new identity explicitly', async () => {
    const wrapper = create();
    await load(wrapper);
    await wrapper.setProps({ authorityKey: 'profile-2', taskId: '16' });
    expect(wrapper.find('[data-native-task-status]').exists()).toBe(false);
    expect(request).toHaveBeenCalledTimes(1);
    request.mockResolvedValueOnce({ data: { ...task(), id: 16 } });
    await load(wrapper);
    expect(request).toHaveBeenLastCalledWith(
      '1',
      'projects/projects/9/tasks/16',
      expect.any(Object)
    );
  });

  it('aborts and ignores a late response from a different account', async () => {
    let finish;
    request.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = create();
    await wrapper.get('[data-load-native-task-state]').trigger('click');
    const signal = request.mock.calls[0][2].signal;
    await wrapper.setProps({ accountId: '2' });
    expect(signal.aborted).toBe(true);
    finish({ data: task() });
    await flushPromises();
    expect(wrapper.find('[data-native-task-status]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC current owner');
  });

  it.each([{ project_id: 10 }, { id: 18 }, { status: 'fabricated_state' }])(
    'rejects a mismatched or unsupported native response %s',
    async invalid => {
      request.mockResolvedValueOnce({ data: { ...task(), ...invalid } });
      const wrapper = create();
      await load(wrapper);
      expect(wrapper.get('[role="alert"]').text()).toContain('ERROR');
      expect(wrapper.find('[data-native-task-status]').exists()).toBe(false);
      expect(wrapper.text()).not.toContain('SYNTHETIC current owner');
    }
  );

  it('preserves an explicit safe read retry after a failed request and prevents concurrent double clicks', async () => {
    let fail;
    request.mockImplementationOnce(
      () =>
        new Promise((resolve, reject) => {
          fail = reject;
        })
    );
    const wrapper = create();
    await wrapper.get('[data-load-native-task-state]').trigger('click');
    await wrapper.get('[data-load-native-task-state]').trigger('click');
    expect(request).toHaveBeenCalledTimes(1);
    fail({ response: { status: 503 } });
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('ERROR');
    await load(wrapper);
    expect(wrapper.get('[data-native-task-status]').text()).toBe(
      'Em andamento'
    );
    expect(request).toHaveBeenCalledTimes(2);
  });
});
