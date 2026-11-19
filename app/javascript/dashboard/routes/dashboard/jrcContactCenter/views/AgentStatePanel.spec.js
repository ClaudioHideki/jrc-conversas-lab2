import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import AgentStatePanel from './AgentStatePanel.vue';
enableAutoUnmount(afterEach);
afterEach(() => vi.useRealTimers());

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { agentState: vi.fn(), updateAgentState: vi.fn() },
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? Object.values(params).join(' ') : key),
  }),
}));

const initialState = {
  state: 'offline',
  state_version: '0',
  provider_confirmed: false,
  eligible: false,
  queues: [],
};

const deferredDialogStub = {
  name: 'DeferredPauseDialog',
  props: [
    'accountId',
    'memberId',
    'contextKey',
    'mode',
    'stateVersion',
    'requestRevision',
    'reasonCode',
    'reasonLabel',
    'queueId',
    'justification',
    'requestId',
  ],
  emits: ['updated', 'close', 'refresh', 'denied'],
  template: '<div data-deferred-dialog-stub />',
};
const deferredState = {
  ...initialState,
  account_user_id: '2',
  state: 'acw',
  state_version: '7',
  can_defer_pause: true,
  pause_request_revision: 'a'.repeat(64),
};
const deferredPanel = () =>
  mount(AgentStatePanel, {
    props: { accountId: '1', canOperate: true },
    global: { stubs: { DeferredPauseDialog: deferredDialogStub } },
  });

describe('AgentStatePanel', () => {
  beforeEach(() => {
    JrcContactCenterAPI.agentState.mockResolvedValue({
      data: { item: initialState },
    });
  });

  it('shows structured reason, pause time and native resume with optimistic version checking', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-10-16T12:00:00Z'));
    JrcContactCenterAPI.agentState.mockResolvedValue({
      data: {
        item: {
          ...initialState,
          state: 'paused',
          reason_code: 'coffee',
          started_at: '2026-10-16T11:59:50Z',
          state_version: '4',
        },
      },
    });
    JrcContactCenterAPI.updateAgentState.mockResolvedValue({
      data: {
        item: { ...initialState, state: 'available', state_version: '5' },
      },
    });
    const wrapper = mount(AgentStatePanel, {
      props: { accountId: 1, canOperate: true },
    });
    await flushPromises();
    expect(wrapper.get('[role="timer"]').text()).toContain('00:00:10');
    await vi.advanceTimersByTimeAsync(2000);
    expect(wrapper.get('[role="timer"]').text()).toContain('00:00:12');
    expect(
      wrapper.get('select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]')
        .element.value
    ).toBe('coffee');
    await wrapper.findAll('button')[0].trigger('click');
    await flushPromises();
    expect(JrcContactCenterAPI.updateAgentState).toHaveBeenCalledWith(
      1,
      expect.objectContaining({
        state: 'available',
        expected_state_version: '4',
      })
    );
    expect(wrapper.emitted('stateChange').at(-1)[0].state).toBe('available');
    expect(wrapper.find('[role="timer"]').exists()).toBe(false);
  });

  it('shows local intent and does not offer writes to a read-only operator', async () => {
    const wrapper = mount(AgentStatePanel, { props: { accountId: '1' } });
    await flushPromises();
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.AGENT.LOCAL_INTENT');
    expect(wrapper.findAll('button')).toHaveLength(0);
    expect(JrcContactCenterAPI.updateAgentState).not.toHaveBeenCalled();
  });

  it('requires a reason before allowing a pause', async () => {
    const wrapper = mount(AgentStatePanel, {
      props: { accountId: '1', canOperate: true },
    });
    await flushPromises();
    const pause = wrapper.findAll('button')[1];
    expect(pause.attributes('disabled')).toBeDefined();
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]')
      .setValue('coffee');
    expect(pause.attributes('disabled')).toBeUndefined();
  });

  it('does not display a response from the previous account after navigation', async () => {
    let resolveFirst;
    JrcContactCenterAPI.agentState.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveFirst = resolve;
        })
    );
    const wrapper = mount(AgentStatePanel, { props: { accountId: '1' } });
    await wrapper.setProps({ accountId: '2' });
    await flushPromises();
    resolveFirst({ data: { item: { ...initialState, state: 'in_call' } } });
    await flushPromises();
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.AGENT.STATES.offline');
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.AGENT.STATES.in_call'
    );
  });

  it('offers the eleven structured reasons and sends the selected reason_code before resuming', async () => {
    JrcContactCenterAPI.updateAgentState
      .mockResolvedValueOnce({
        data: {
          item: {
            ...initialState,
            state: 'paused',
            state_version: '1',
            reason_code: 'coffee',
          },
        },
      })
      .mockResolvedValueOnce({
        data: {
          item: { ...initialState, state: 'available', state_version: '2' },
        },
      });
    const wrapper = mount(AgentStatePanel, {
      props: { accountId: '1', canOperate: true },
    });
    await flushPromises();
    const reasons = wrapper.get(
      'select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]'
    );
    expect(
      reasons.findAll('option').map(option => option.element.value)
    ).toEqual([
      '',
      'bathroom',
      'coffee',
      'lunch',
      'meeting',
      'training',
      'feedback',
      'backoffice',
      'internal_support',
      'technical_issue',
      'rest',
      'end_shift',
    ]);
    await reasons.setValue('coffee');
    await wrapper.findAll('button')[1].trigger('click');
    await flushPromises();
    expect(JrcContactCenterAPI.updateAgentState).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ state: 'paused', reason_code: 'coffee' })
    );
    await wrapper.findAll('button')[0].trigger('click');
    await flushPromises();
    expect(JrcContactCenterAPI.updateAgentState).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({
        state: 'available',
        expected_state_version: '1',
      })
    );
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.AGENT.STATES.available'
    );
  });

  it('requires a structured selection when restoring a legacy free-text pause reason', async () => {
    JrcContactCenterAPI.agentState.mockResolvedValueOnce({
      data: {
        item: {
          ...initialState,
          state: 'paused',
          reason_code: 'legacy free text',
        },
      },
    });
    const wrapper = mount(AgentStatePanel, {
      props: { accountId: '1', canOperate: true },
    });
    await flushPromises();
    expect(wrapper.findAll('button')[1].attributes('disabled')).toBeDefined();
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]')
      .setValue('coffee');
    expect(wrapper.findAll('button')[1].attributes('disabled')).toBeUndefined();
  });

  it('keeps legacy reasons until explicit catalog enforcement and narrows configured options by selected queue', async () => {
    JrcContactCenterAPI.agentState.mockResolvedValue({
      data: {
        item: {
          ...initialState,
          queues: [
            { id: '1', name: 'SYNTHETIC A' },
            { id: '2', name: 'SYNTHETIC B' },
          ],
          pause_catalog: {
            enforced: false,
            entries: [
              {
                code: 'synthetic_a',
                name: 'SYNTHETIC A reason',
                scope_queue_ids: ['1'],
                all_queues: false,
              },
            ],
          },
        },
      },
    });
    const wrapper = mount(AgentStatePanel, {
      props: { accountId: '1', canOperate: true },
    });
    await flushPromises();
    const reasons = wrapper.get(
      'select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]'
    );
    expect(reasons.find('option[value="coffee"]').exists()).toBe(true);
    expect(reasons.find('option[value="synthetic_a"]').exists()).toBe(true);
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.CARDS.QUEUES"]')
      .setValue('2');
    expect(reasons.find('option[value="synthetic_a"]').exists()).toBe(false);
    expect(reasons.find('option[value="coffee"]').exists()).toBe(true);
  });

  it('shows the immutable local reason and a maximum-time notice without automatically resuming distribution', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-11-18T12:10:00Z'));
    JrcContactCenterAPI.agentState.mockResolvedValue({
      data: {
        item: {
          ...initialState,
          state: 'paused',
          reason_code: 'synthetic_old',
          started_at: '2026-11-18T12:00:00Z',
          pause_catalog: { enforced: true, entries: [] },
          pause_definition: {
            name: 'SYNTHETIC historic reason',
            maximum_minutes: 5,
          },
        },
      },
    });
    const wrapper = mount(AgentStatePanel, {
      props: { accountId: '1', canOperate: true },
    });
    await flushPromises();
    expect(wrapper.get('[role="timer"]').text()).toContain(
      'SYNTHETIC historic reason'
    );
    expect(wrapper.get('[data-pause-exceeded]').text()).toContain(
      'JRC_CONTACT_CENTER.PAUSE_CATALOG.EXCEEDED'
    );
    expect(
      wrapper
        .get('select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]')
        .find('option[value="coffee"]')
        .exists()
    ).toBe(false);
    expect(wrapper.findAll('button')[1].attributes('disabled')).toBeDefined();
    await vi.advanceTimersByTimeAsync(2000);
    expect(JrcContactCenterAPI.updateAgentState).not.toHaveBeenCalled();
  });

  it('requires private text only under an enforced per-reason policy, preserves a failed draft and renders the persisted self response', async () => {
    const configured = {
      ...initialState,
      pause_catalog: {
        enforced: true,
        entries: [
          {
            code: 'synthetic',
            name: 'SYNTHETIC',
            all_queues: true,
            scope_queue_ids: [],
            justification_required: true,
          },
        ],
      },
    };
    JrcContactCenterAPI.agentState.mockResolvedValueOnce({
      data: { item: configured },
    });
    const wrapper = mount(AgentStatePanel, {
      props: { accountId: '1', canOperate: true },
    });
    await flushPromises();
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]')
      .setValue('synthetic');
    const input = wrapper.get(
      'textarea[aria-label="JRC_CONTACT_CENTER.PAUSE_CATALOG.JUSTIFICATION"]'
    );
    const pause = wrapper.findAll('button')[1];
    expect(input.attributes('maxlength')).toBe('1000');
    expect(pause.attributes('disabled')).toBeDefined();
    await input.setValue('  SYNTHETIC private draft  ');
    expect(pause.attributes('disabled')).toBeUndefined();
    JrcContactCenterAPI.updateAgentState.mockRejectedValueOnce({
      response: { data: { error: 'pause_justification_required' } },
    });
    await pause.trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      'JRC_CONTACT_CENTER.PAUSE_CATALOG.JUSTIFICATION_ERROR'
    );
    expect(input.element.value).toBe('  SYNTHETIC private draft  ');
    JrcContactCenterAPI.updateAgentState.mockResolvedValueOnce({
      data: {
        item: {
          ...configured,
          state: 'paused',
          state_version: '1',
          reason_code: 'synthetic',
          pause_definition: {
            name: 'SYNTHETIC',
            justification: 'SYNTHETIC private draft',
          },
        },
      },
    });
    await pause.trigger('click');
    await flushPromises();
    expect(JrcContactCenterAPI.updateAgentState).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ justification: 'SYNTHETIC private draft' })
    );
    expect(wrapper.get('[data-own-pause-justification]').text()).toContain(
      'SYNTHETIC private draft'
    );
    expect(input.element.value).toBe('');
    await wrapper.setProps({ accountId: '2' });
    await flushPromises();
    expect(wrapper.find('[data-own-pause-justification]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC private draft');
  });

  it('keeps the new field optional before enforcement and clears its draft on queue or operating-authority changes', async () => {
    JrcContactCenterAPI.agentState.mockResolvedValue({
      data: {
        item: {
          ...initialState,
          queues: [
            { id: '1', name: 'SYNTHETIC A' },
            { id: '2', name: 'SYNTHETIC B' },
          ],
          pause_catalog: {
            enforced: false,
            entries: [
              {
                code: 'synthetic',
                name: 'SYNTHETIC',
                all_queues: true,
                scope_queue_ids: [],
                justification_required: true,
              },
            ],
          },
        },
      },
    });
    const wrapper = mount(AgentStatePanel, {
      props: { accountId: '1', canOperate: true },
    });
    await flushPromises();
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]')
      .setValue('synthetic');
    expect(wrapper.findAll('button')[1].attributes('disabled')).toBeUndefined();
    const input = wrapper.get('textarea');
    await input.setValue('SYNTHETIC unsaved');
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.CARDS.QUEUES"]')
      .setValue('2');
    expect(input.element.value).toBe('');
    await input.setValue('SYNTHETIC revoked');
    await wrapper.setProps({ canOperate: false });
    expect(wrapper.find('textarea').exists()).toBe(false);
    await wrapper.setProps({ canOperate: true });
    await flushPromises();
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]')
      .setValue('synthetic');
    expect(wrapper.get('textarea').element.value).toBe('');
  });

  it('does not restore private text from an old write response after operating authority changes', async () => {
    const configured = {
      ...initialState,
      pause_catalog: {
        enforced: false,
        entries: [
          {
            code: 'synthetic',
            name: 'SYNTHETIC',
            all_queues: true,
            scope_queue_ids: [],
          },
        ],
      },
    };
    JrcContactCenterAPI.agentState.mockResolvedValue({
      data: { item: configured },
    });
    let resolveWrite;
    JrcContactCenterAPI.updateAgentState.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveWrite = resolve;
        })
    );
    const wrapper = mount(AgentStatePanel, {
      props: { accountId: '1', canOperate: true },
    });
    await flushPromises();
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]')
      .setValue('synthetic');
    await wrapper.get('textarea').setValue('SYNTHETIC obsolete private text');
    await wrapper.findAll('button')[1].trigger('click');
    await wrapper.setProps({ canOperate: false });
    await flushPromises();
    resolveWrite({
      data: {
        item: {
          ...configured,
          state: 'paused',
          state_version: '7',
          pause_definition: {
            name: 'SYNTHETIC',
            justification: 'SYNTHETIC obsolete private text',
          },
        },
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-own-pause-justification]').exists()).toBe(false);
    await wrapper.setProps({ canOperate: true });
    await flushPromises();
    expect(wrapper.find('[data-own-pause-justification]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC obsolete private text');
  });
});

describe('deferred pause native panel wiring (mocked presentation only)', () => {
  beforeEach(() => {
    JrcContactCenterAPI.agentState
      .mockReset()
      .mockResolvedValue({ data: { item: { ...deferredState } } });
    JrcContactCenterAPI.updateAgentState.mockReset();
  });

  it('opens a review with the current member, state revision and selection without requesting a premature pause', async () => {
    const wrapper = deferredPanel();
    await flushPromises();
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]')
      .setValue('coffee');
    await wrapper.findAll('button')[1].trigger('click');
    const dialog = wrapper.findComponent(deferredDialogStub);
    expect(dialog.exists()).toBe(true);
    expect(dialog.props()).toMatchObject({
      accountId: '1',
      memberId: '2',
      mode: 'request',
      stateVersion: '7',
      reasonCode: 'coffee',
    });
    expect(JrcContactCenterAPI.updateAgentState).not.toHaveBeenCalled();
  });

  it('shows the own durable pending request while keeping manual availability changes disabled', async () => {
    const wrapper = deferredPanel();
    await flushPromises();
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]')
      .setValue('coffee');
    await wrapper.findAll('button')[1].trigger('click');
    const dialog = wrapper.findComponent(deferredDialogStub);
    const token = dialog.props('contextKey');
    dialog.vm.$emit(
      'updated',
      {
        ...deferredState,
        deferred_pause_request: {
          request_id: 'SYNTHETIC request',
          state: 'pending',
          reason_label: 'SYNTHETIC private reason',
        },
      },
      token
    );
    dialog.vm.$emit('close', token);
    await flushPromises();
    expect(wrapper.get('[data-deferred-pause-pending]').text()).toContain(
      'SYNTHETIC private reason'
    );
    expect(
      wrapper
        .findAll('button')
        .slice(-3)
        .every(button => button.attributes('disabled') !== undefined)
    ).toBe(true);
    await wrapper.get('[data-deferred-pause-cancel]').trigger('click');
    expect(wrapper.findComponent(deferredDialogStub).props()).toMatchObject({
      mode: 'cancel',
      requestId: 'SYNTHETIC request',
    });
    expect(JrcContactCenterAPI.updateAgentState).not.toHaveBeenCalled();
  });

  it('ignores old dialog updates and close events after switching account and opening a new review', async () => {
    JrcContactCenterAPI.agentState
      .mockResolvedValueOnce({ data: { item: { ...deferredState } } })
      .mockResolvedValueOnce({
        data: { item: { ...deferredState, account_user_id: '3' } },
      });
    const wrapper = deferredPanel();
    await flushPromises();
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]')
      .setValue('coffee');
    await wrapper.findAll('button')[1].trigger('click');
    const previous = wrapper.findComponent(deferredDialogStub);
    const token = previous.props('contextKey');
    await wrapper.setProps({ accountId: '2' });
    await flushPromises();
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]')
      .setValue('coffee');
    await wrapper.findAll('button')[1].trigger('click');
    previous.vm.$emit('updated', { ...deferredState, state: 'paused' }, token);
    previous.vm.$emit('denied', token);
    previous.vm.$emit('close', token);
    await flushPromises();
    expect(wrapper.findComponent(deferredDialogStub).props()).toMatchObject({
      accountId: '2',
      memberId: '3',
    });
    expect(wrapper.emitted('stateChange').at(-1)[0].account_user_id).toBe('3');
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.DEFERRED_PAUSE.DENIED'
    );
  });

  it('clears sensitive selection after a current operating-authority denial', async () => {
    const wrapper = deferredPanel();
    await flushPromises();
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]')
      .setValue('coffee');
    await wrapper.findAll('button')[1].trigger('click');
    const dialog = wrapper.findComponent(deferredDialogStub);
    dialog.vm.$emit('denied', dialog.props('contextKey'));
    await flushPromises();
    expect(wrapper.findComponent(deferredDialogStub).exists()).toBe(false);
    expect(wrapper.find('select').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.DEFERRED_PAUSE.DENIED'
    );
    expect(JrcContactCenterAPI.updateAgentState).not.toHaveBeenCalled();
  });
});

describe('deferred pause state observation (mocked read-only presentation)', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    JrcContactCenterAPI.agentState.mockReset();
    JrcContactCenterAPI.updateAgentState.mockReset();
  });
  const pendingState = {
    ...deferredState,
    deferred_pause_request: {
      request_id: 'SYNTHETIC pending observation',
      state: 'pending',
      reason_label: 'SYNTHETIC private observation',
    },
  };

  it('observes the eventual native paused state without issuing a transition or clearing unrelated manual input', async () => {
    JrcContactCenterAPI.agentState
      .mockResolvedValueOnce({ data: { account_id: '1', item: pendingState } })
      .mockResolvedValueOnce({
        data: {
          account_id: '1',
          item: {
            ...deferredState,
            state: 'paused',
            can_defer_pause: false,
            state_version: '9',
            reason_code: 'lunch',
            started_at: '2026-11-19T12:00:00Z',
          },
        },
      });
    const wrapper = deferredPanel();
    await flushPromises();
    expect(wrapper.find('[data-deferred-pause-pending]').exists()).toBe(true);
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]')
      .setValue('coffee');
    await vi.advanceTimersByTimeAsync(5000);
    await flushPromises();
    expect(wrapper.find('[data-deferred-pause-pending]').exists()).toBe(false);
    expect(wrapper.find('[role="timer"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.AGENT.STATES.paused');
    expect(JrcContactCenterAPI.updateAgentState).not.toHaveBeenCalled();
    expect(JrcContactCenterAPI.agentState).toHaveBeenCalledTimes(2);
    expect(
      wrapper.get('select[aria-label="JRC_CONTACT_CENTER.AGENT.REASON"]')
        .element.value
    ).toBe('coffee');
  });

  it('stops observation on failure until an explicit refresh and never retries writes', async () => {
    JrcContactCenterAPI.agentState
      .mockResolvedValueOnce({ data: { account_id: '1', item: pendingState } })
      .mockRejectedValueOnce(new Error('SYNTHETIC read failure'))
      .mockResolvedValueOnce({ data: { account_id: '1', item: pendingState } });
    const wrapper = deferredPanel();
    await flushPromises();
    await vi.advanceTimersByTimeAsync(15000);
    await flushPromises();
    expect(JrcContactCenterAPI.agentState).toHaveBeenCalledTimes(2);
    expect(
      wrapper.get('[data-deferred-pause-cancel]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      'JRC_CONTACT_CENTER.COMMON.ERROR'
    );
    expect(wrapper.get('[role="alert"]').find('button').exists()).toBe(false);
    await wrapper.get('[data-agent-state-refresh]').trigger('click');
    await flushPromises();
    expect(JrcContactCenterAPI.agentState).toHaveBeenCalledTimes(3);
    expect(
      wrapper.get('[data-deferred-pause-cancel]').attributes('disabled')
    ).toBeUndefined();
    expect(JrcContactCenterAPI.updateAgentState).not.toHaveBeenCalled();
  });

  it('clears previous private state when the authenticated member changes within the same account', async () => {
    JrcContactCenterAPI.agentState
      .mockResolvedValueOnce({ data: { account_id: '1', item: pendingState } })
      .mockResolvedValueOnce({
        data: {
          account_id: '1',
          item: { ...deferredState, account_user_id: '99' },
        },
      });
    const wrapper = deferredPanel();
    await flushPromises();
    await vi.advanceTimersByTimeAsync(5000);
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC private observation');
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.DEFERRED_PAUSE.CONTEXT_CHANGED'
    );
    expect(wrapper.find('select').exists()).toBe(false);
    expect(JrcContactCenterAPI.updateAgentState).not.toHaveBeenCalled();
  });

  it('clears the pending private projection when the server reports view-only authority', async () => {
    JrcContactCenterAPI.agentState
      .mockResolvedValueOnce({ data: { account_id: '1', item: pendingState } })
      .mockResolvedValueOnce({
        data: {
          account_id: '1',
          item: { ...deferredState, pause_catalog: null },
        },
      });
    const wrapper = deferredPanel();
    await flushPromises();
    await vi.advanceTimersByTimeAsync(5000);
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC private observation');
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.DEFERRED_PAUSE.DENIED'
    );
    expect(wrapper.find('select').exists()).toBe(false);
  });
});
