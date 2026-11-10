import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createStore } from 'vuex';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import RetentionPanel from '../RetentionPanel.vue';
import API from 'dashboard/api/jrcRelationship';

let route;
vi.mock('dashboard/api/jrcRelationship', () => ({
  default: {
    retention: vi.fn(),
    retentionStatus: vi.fn(),
    startRetentionHistory: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({ useRoute: () => route }));

let wrapper;
let store;
const report = {
  metric: 'TRR',
  available: true,
  from: '2026-11-01',
  to: '2026-11-10',
  timezone: 'UTC',
  initial: 10,
  retained: 7,
  exits: 3,
  value: 70,
};

beforeEach(() => {
  vi.resetAllMocks();
  route = reactive({ params: { accountId: '1' } });
  store = createStore({
    state: { role: 'agent' },
    getters: {
      getCurrentUserID: () => 7,
      getCurrentRole: state => state.role,
      getCurrentUser: () => ({ accounts: [{ id: 1, role: 'agent' }] }),
    },
  });
  API.retentionStatus.mockResolvedValue({ data: { can_start: false } });
  API.retention.mockResolvedValue({ data: report });
});

afterEach(() => wrapper?.unmount());

describe('retention panel authorization and real zero display', () => {
  const render = async () => {
    wrapper = mount(RetentionPanel, {
      props: { metadata: { can_configure: true } },
      global: { plugins: [store] },
    });
    await flushPromises();
  };

  const calculate = async () => {
    await wrapper.get('input[type="date"]').setValue('2026-11-01');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
  };

  it('does not start history or calculate a report merely by opening the panel', async () => {
    await render();
    expect(API.retentionStatus).toHaveBeenCalledWith('1');
    expect(API.retention).not.toHaveBeenCalled();
    expect(API.startRetentionHistory).not.toHaveBeenCalled();
  });

  it('shows zero only when confirmed by a nonempty eligible cohort', async () => {
    API.retention.mockResolvedValue({
      data: { ...report, retained: 0, exits: 10, value: 0 },
    });
    await render();
    await calculate();
    expect(wrapper.text()).toContain('0%');
    expect(API.retention).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({ period: 'monthly', reference: '2026-11-01' }),
      expect.any(Object)
    );
  });

  it('keeps unavailable history distinct from a confirmed zero', async () => {
    API.retention.mockResolvedValue({
      data: {
        ...report,
        available: false,
        value: null,
        code: 'insufficient_history',
      },
    });
    await render();
    await calculate();
    expect(wrapper.text()).not.toContain('0%');
    expect(wrapper.text()).toContain('—');
  });

  it('clears an already displayed report when native authorization metadata changes', async () => {
    await render();
    await calculate();
    expect(wrapper.text()).toContain('70%');
    await wrapper.setProps({ metadata: { can_configure: false } });
    await flushPromises();
    expect(wrapper.text()).not.toContain('70%');
    expect(API.retentionStatus).toHaveBeenCalledTimes(2);
  });

  it('discards a pending report after native authorization metadata changes', async () => {
    let resolve;
    API.retention.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    await render();
    await calculate();
    await wrapper.setProps({ metadata: { can_configure: false } });
    resolve({ data: report });
    await flushPromises();
    expect(wrapper.text()).not.toContain('70%');
  });

  it('clears data after a native profile change without starting observation', async () => {
    await render();
    await calculate();
    store.state.role = 'administrator';
    await flushPromises();
    expect(wrapper.text()).not.toContain('70%');
    expect(API.startRetentionHistory).not.toHaveBeenCalled();
  });

  it('requires a reason and explicit confirmation before requesting a baseline', async () => {
    API.retentionStatus.mockResolvedValue({ data: { can_start: true } });
    API.startRetentionHistory.mockResolvedValue({
      data: { started_at: '2026-11-10T13:00:00Z' },
    });
    await render();
    const form = wrapper.findAll('form')[1];
    expect(form.get('button').attributes('disabled')).toBeDefined();
    await form.get('textarea').setValue('Synthetic baseline approval');
    await form.get('input[type="checkbox"]').setValue(true);
    await form.trigger('submit');
    await flushPromises();
    expect(API.startRetentionHistory).toHaveBeenCalledWith(
      '1',
      'Synthetic baseline approval'
    );
    expect(wrapper.text()).toContain('2026-11-10T13:00:00Z');
  });
});
