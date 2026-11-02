import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConnectionPanel from '../ConnectionPanel.vue';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';

vi.mock('dashboard/api/jrcBroker', () => ({ createJrcBrokerApi: vi.fn() }));
const health = {
  instanceStatus: 'DISCONNECTED',
  integrationStatus: 'READY',
  transportStatus: 'UNVERIFIED',
  identityStatus: 'UNVERIFIED',
  allowedActions: ['status', 'pair'],
};
let api;
let wrapper;

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date('2030-01-01T00:00:00Z'));
  api = {
    status: vi.fn().mockResolvedValue({ ...health }),
    pair: vi.fn().mockResolvedValue({
      action: {
        type: 'PAIRING_CODE',
        code: 'ABCD-1234',
        expiresAt: '2030-01-01T00:00:10Z',
      },
    }),
    pairOperation: vi.fn(),
  };
  createJrcBrokerApi.mockReturnValue(api);
});
afterEach(() => {
  wrapper?.unmount();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe('native pairing lifecycle', () => {
  it('publishes real health and confirms an explicit reconnection once without treating delivery as verified', async () => {
    wrapper = mount(ConnectionPanel, { props: { accountId: 1, inboxId: 2 } });
    await flushPromises();
    expect(wrapper.emitted('health')).toEqual([
      [{ accountId: 1, inboxId: 2, health }],
    ]);
    expect(wrapper.emitted('reconnected')).toBeUndefined();
    await wrapper.get('[data-testid="pair"]').trigger('click');
    await flushPromises();
    api.status.mockResolvedValue({
      ...health,
      instanceStatus: 'CONNECTED',
      identityStatus: 'CONFIRMATION_REQUIRED',
      identityApproved: true,
    });
    await vi.advanceTimersByTimeAsync(3000);
    expect(wrapper.emitted('reconnected')).toBeUndefined();
    expect(wrapper.get('[data-testid="connection-health"]').text()).toContain(
      'Administrator approval required'
    );
    const connected = {
      ...health,
      instanceStatus: 'CONNECTED',
      identityStatus: 'CONFIRMED',
      identityApproved: true,
      allowedActions: ['status'],
    };
    api.status.mockResolvedValue(connected);
    await vi.advanceTimersByTimeAsync(3000);
    expect(wrapper.emitted('reconnected')).toEqual([
      [{ accountId: 1, inboxId: 2, health: connected }],
    ]);
    expect(wrapper.emitted('health').at(-1)[0].health.transportStatus).toBe(
      'UNVERIFIED'
    );
    await vi.advanceTimersByTimeAsync(3000);
    expect(wrapper.emitted('reconnected')).toHaveLength(1);
    expect(api.pair).toHaveBeenCalledTimes(1);
  });

  it('does not announce reconnection on an already connected initial read or an inactive binding', async () => {
    api.status.mockResolvedValue({
      ...health,
      instanceStatus: 'CONNECTED',
      identityApproved: true,
    });
    wrapper = mount(ConnectionPanel, { props: { accountId: 1, inboxId: 2 } });
    await flushPromises();
    expect(wrapper.emitted('reconnected')).toBeUndefined();
    api.status.mockResolvedValue({ ...health });
    await wrapper.setProps({ inboxId: 3 });
    await flushPromises();
    await wrapper.get('[data-testid="pair"]').trigger('click');
    api.status.mockResolvedValue({
      ...health,
      instanceStatus: 'CONNECTED',
      identityApproved: true,
      integrationStatus: 'DISABLED',
    });
    await flushPromises();
    await vi.advanceTimersByTimeAsync(3000);
    expect(wrapper.emitted('reconnected')).toBeUndefined();
  });

  it('keeps the existing poll alive when presentation changes and separates status from actions', async () => {
    wrapper = mount(ConnectionPanel, {
      props: { accountId: 1, inboxId: 2, presentation: 'overview' },
    });
    await flushPromises();
    expect(wrapper.find('[data-testid="pair"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="connection-health"]').exists()).toBe(
      true
    );
    const calls = api.status.mock.calls.length;
    await wrapper.setProps({ presentation: 'configuration' });
    expect(wrapper.find('[data-testid="pair"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="connection-health"]').exists()).toBe(
      false
    );
    expect(api.status).toHaveBeenCalledTimes(calls);
    await vi.advanceTimersByTimeAsync(3000);
    expect(api.status).toHaveBeenCalledTimes(calls + 1);
  });

  it('does not submit another pairing request after a response timeout without an operation ID', async () => {
    api.pair.mockRejectedValueOnce(new Error('timeout'));
    wrapper = mount(ConnectionPanel, { props: { accountId: 1, inboxId: 2 } });
    await flushPromises();
    await wrapper.get('[data-testid="pair"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('The result is uncertain');
    expect(
      wrapper.get('[data-testid="pair"]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.find('[data-testid="verify-pair-operation"]').exists()).toBe(
      false
    );
    await vi.advanceTimersByTimeAsync(15000);
    expect(api.pair).toHaveBeenCalledTimes(1);
  });
  it('explains a conflict on a new pairing request without retrying it', async () => {
    api.pair.mockRejectedValueOnce({ response: { status: 409 } });
    wrapper = mount(ConnectionPanel, { props: { accountId: 1, inboxId: 2 } });
    await flushPromises();
    await wrapper.get('[data-testid="pair"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(
      'The previous connection attempt needs review'
    );
    expect(api.pair).toHaveBeenCalledTimes(1);
  });
  it('checks asynchronous pairing by GET without repeating POST or promising a stored QR', async () => {
    api.pair.mockResolvedValueOnce({
      operationId: '11111111-1111-4111-8111-111111111111',
      action: { type: 'NONE', reason: 'CONNECTION_PENDING' },
    });
    api.pairOperation
      .mockResolvedValueOnce({
        operationId: '11111111-1111-4111-8111-111111111111',
        state: 'PENDING',
      })
      .mockResolvedValueOnce({
        operationId: '11111111-1111-4111-8111-111111111111',
        state: 'SUCCEEDED',
      });
    wrapper = mount(ConnectionPanel, { props: { accountId: 1, inboxId: 2 } });
    await flushPromises();
    await wrapper.get('[data-testid="pair"]').trigger('click');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(3000);
    expect(api.pair).toHaveBeenCalledTimes(1);
    expect(api.pairOperation).toHaveBeenCalledWith(
      2,
      '11111111-1111-4111-8111-111111111111',
      expect.anything()
    );
    expect(wrapper.text()).not.toContain('ABCD-1234');
    await vi.advanceTimersByTimeAsync(3000);
    expect(wrapper.text()).toContain('Request a new code');
    expect(api.pair).toHaveBeenCalledTimes(1);
    await wrapper.get('[data-testid="pair"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('ABCD-1234');
    expect(api.pair).toHaveBeenCalledTimes(2);
    expect(api.pair.mock.calls[1][1]).not.toBe(api.pair.mock.calls[0][1]);
  });
  it('lets the user verify an uncertain operation without automatically starting another connection', async () => {
    let resolved = false;
    api.pair.mockResolvedValueOnce({
      operationId: '11111111-1111-4111-8111-111111111111',
      action: { type: 'NONE', reason: 'CONNECTION_PENDING' },
    });
    api.pairOperation.mockImplementation(async () => ({
      operationId: '11111111-1111-4111-8111-111111111111',
      state: resolved ? 'SUCCEEDED' : 'PENDING',
    }));
    wrapper = mount(ConnectionPanel, { props: { accountId: 1, inboxId: 2 } });
    await flushPromises();
    await wrapper.get('[data-testid="pair"]').trigger('click');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(61_000);
    expect(wrapper.text()).toContain('The result is uncertain');
    resolved = true;
    await wrapper.get('[data-testid="verify-pair-operation"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Request a new code');
    expect(
      wrapper.get('[data-testid="pair"]').attributes('disabled')
    ).toBeUndefined();
    expect(api.pair).toHaveBeenCalledTimes(1);
  });
  it('requires a read-only check before an explicit new attempt after the operation becomes uncertain', async () => {
    let operationState = 'PENDING';
    const operationId = '11111111-1111-4111-8111-111111111111';
    api.pair
      .mockResolvedValueOnce({
        operationId,
        action: { type: 'NONE', reason: 'CONNECTION_PENDING' },
      })
      .mockRejectedValueOnce({ response: { status: 409 } });
    api.pairOperation.mockImplementation(async () => ({
      operationId,
      state: operationState,
      reconciliationRequired: operationState === 'UNKNOWN',
    }));
    wrapper = mount(ConnectionPanel, { props: { accountId: 1, inboxId: 2 } });
    await flushPromises();
    await wrapper.get('[data-testid="pair"]').trigger('click');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(61_000);
    expect(
      wrapper.get('[data-testid="pair"]').attributes('disabled')
    ).toBeDefined();
    expect(api.pair).toHaveBeenCalledTimes(1);

    operationState = 'UNKNOWN';
    await wrapper.get('[data-testid="verify-pair-operation"]').trigger('click');
    await flushPromises();
    expect(api.status).toHaveBeenCalled();
    expect(api.pairOperation).toHaveBeenCalledWith(
      2,
      operationId,
      expect.anything()
    );
    expect(api.pair).toHaveBeenCalledTimes(1);
    expect(
      wrapper.get('[data-testid="pair"]').attributes('disabled')
    ).toBeUndefined();

    await wrapper.get('[data-testid="pair"]').trigger('click');
    await flushPromises();
    expect(api.pair).toHaveBeenCalledTimes(2);
    expect(api.pair.mock.calls[1][1]).not.toBe(api.pair.mock.calls[0][1]);
    expect(wrapper.text()).toContain(
      'The previous connection attempt needs review'
    );
    expect(
      wrapper.get('[data-testid="pair"]').attributes('disabled')
    ).toBeDefined();
  });
  it('finishes an explicit check even when a scheduled status read is already in flight', async () => {
    let finishStatus;
    let operationState = 'PENDING';
    const operationId = '11111111-1111-4111-8111-111111111111';
    api.pair.mockResolvedValueOnce({
      operationId,
      action: { type: 'NONE', reason: 'CONNECTION_PENDING' },
    });
    api.pairOperation.mockImplementation(async () => ({
      operationId,
      state: operationState,
      reconciliationRequired: operationState === 'UNKNOWN',
    }));
    wrapper = mount(ConnectionPanel, { props: { accountId: 1, inboxId: 2 } });
    await flushPromises();
    await wrapper.get('[data-testid="pair"]').trigger('click');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(61_000);
    api.status.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finishStatus = resolve;
        })
    );
    document.dispatchEvent(new Event('visibilitychange'));
    await flushPromises();
    operationState = 'UNKNOWN';
    await wrapper.get('[data-testid="verify-pair-operation"]').trigger('click');
    finishStatus({ ...health });
    await flushPromises();
    await vi.advanceTimersByTimeAsync(3000);
    expect(api.pair).toHaveBeenCalledTimes(1);
    expect(
      wrapper.get('[data-testid="pair"]').attributes('disabled')
    ).toBeUndefined();
  });
  it('displays a late one-time pairing code from one authorized operation read', async () => {
    let complete;
    api.pair.mockResolvedValueOnce({
      operationId: '11111111-1111-4111-8111-111111111111',
      action: { type: 'NONE', reason: 'CONNECTION_PENDING' },
    });
    api.pairOperation.mockImplementation(
      () =>
        new Promise(resolve => {
          complete = resolve;
        })
    );
    wrapper = mount(ConnectionPanel, { props: { accountId: 1, inboxId: 2 } });
    await flushPromises();
    await wrapper.get('[data-testid="pair"]').trigger('click');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(3000);
    document.dispatchEvent(new Event('visibilitychange'));
    await flushPromises();
    expect(api.pairOperation).toHaveBeenCalledTimes(1);
    complete({
      operationId: '11111111-1111-4111-8111-111111111111',
      state: 'SUCCEEDED',
      action: {
        type: 'PAIRING_CODE',
        code: 'LATE-1234',
        expiresAt: '2030-01-01T00:00:30Z',
      },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('LATE-1234');
    expect(api.pair).toHaveBeenCalledTimes(1);
  });
  it('continues polling the same operation after a temporary progress error', async () => {
    api.pair.mockResolvedValueOnce({
      operationId: '11111111-1111-4111-8111-111111111111',
      action: { type: 'NONE', reason: 'CONNECTION_PENDING' },
    });
    api.pairOperation
      .mockRejectedValueOnce({ response: { status: 503 } })
      .mockResolvedValueOnce({
        operationId: '11111111-1111-4111-8111-111111111111',
        state: 'SUCCEEDED',
        action: {
          type: 'PAIRING_CODE',
          code: 'LATE-1234',
          expiresAt: '2030-01-01T00:00:30Z',
        },
      });
    wrapper = mount(ConnectionPanel, { props: { accountId: 1, inboxId: 2 } });
    await flushPromises();
    await wrapper.get('[data-testid="pair"]').trigger('click');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(9000);
    expect(api.pairOperation).toHaveBeenCalledTimes(2);
    expect(api.pair).toHaveBeenCalledTimes(1);
    expect(wrapper.text()).toContain('LATE-1234');
  });
  it('suspends polling while hidden and clears the code on logout', async () => {
    const store = createStore({ mutations: { LOGOUT: () => {} } });
    wrapper = mount(ConnectionPanel, {
      props: { accountId: 1, inboxId: 2 },
      global: { plugins: [store] },
    });
    await flushPromises();
    await wrapper.get('[data-testid="pair"]').trigger('click');
    await flushPromises();
    vi.spyOn(document, 'hidden', 'get').mockReturnValue(true);
    document.dispatchEvent(new Event('visibilitychange'));
    const calls = api.status.mock.calls.length;
    await vi.advanceTimersByTimeAsync(5000);
    expect(api.status).toHaveBeenCalledTimes(calls);
    store.commit('LOGOUT');
    await flushPromises();
    expect(wrapper.text()).not.toContain('ABCD-1234');
    wrapper.unmount();
    await vi.advanceTimersByTimeAsync(15000);
    expect(api.status).toHaveBeenCalledTimes(calls);
  });

  it('requires fresh confirmation if the observed business identity changes while the dialog is open', async () => {
    api.status.mockResolvedValue({
      ...health,
      allowedActions: ['status', 'manage'],
      identityStatus: 'CONFIRMATION_REQUIRED',
      identityRevision: 2,
      observedNumberSuffix: '1111',
    });
    wrapper = mount(ConnectionPanel, { props: { accountId: 1, inboxId: 2 } });
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Confirm business number')
      .trigger('click');
    await wrapper.get('input[type="checkbox"]').setValue(true);
    api.status.mockResolvedValue({
      ...health,
      allowedActions: ['status', 'manage'],
      identityStatus: 'CONFIRMATION_REQUIRED',
      identityRevision: 3,
      observedNumberSuffix: '2222',
    });
    await vi.advanceTimersByTimeAsync(3000);
    expect(wrapper.find('input[type="checkbox"]').exists()).toBe(false);
  });

  it('removes a displayed code when the next status no longer grants pair', async () => {
    wrapper = mount(ConnectionPanel, { props: { accountId: 1, inboxId: 2 } });
    await flushPromises();
    await wrapper.get('[data-testid="pair"]').trigger('click');
    await flushPromises();
    api.status.mockResolvedValue({ ...health, allowedActions: ['status'] });
    await vi.advanceTimersByTimeAsync(3000);
    expect(wrapper.text()).not.toContain('ABCD-1234');
    expect(wrapper.find('[data-testid="pair"]').exists()).toBe(false);
  });

  it('polls only GET, requires an explicit click and removes an expired code', async () => {
    wrapper = mount(ConnectionPanel, { props: { accountId: 1, inboxId: 2 } });
    await flushPromises();
    expect(api.pair).not.toHaveBeenCalled();
    await wrapper.get('[data-testid="pair"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('ABCD-1234');
    await vi.advanceTimersByTimeAsync(11000);
    expect(wrapper.text()).not.toContain('ABCD-1234');
    expect(api.pair).toHaveBeenCalledTimes(1);
    expect(api.status.mock.calls.length).toBeGreaterThan(1);
  });

  it('discards a late pair response after changing account or inbox', async () => {
    let finish;
    api.pair.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    wrapper = mount(ConnectionPanel, { props: { accountId: 1, inboxId: 2 } });
    await flushPromises();
    await wrapper.get('[data-testid="pair"]').trigger('click');
    await wrapper.setProps({ accountId: 3, inboxId: 4 });
    await flushPromises();
    finish({
      action: {
        type: 'PAIRING_CODE',
        code: 'STALE',
        expiresAt: '2030-01-01T00:00:30Z',
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('STALE');
  });

  it('clears codes on connection, denied permission and unmount, and stops polling on forbidden', async () => {
    wrapper = mount(ConnectionPanel, { props: { accountId: 1, inboxId: 2 } });
    await flushPromises();
    await wrapper.get('[data-testid="pair"]').trigger('click');
    await flushPromises();
    api.status.mockResolvedValue({ ...health, instanceStatus: 'CONNECTED' });
    await vi.advanceTimersByTimeAsync(3000);
    expect(wrapper.text()).not.toContain('ABCD-1234');
    api.status.mockRejectedValue({ response: { status: 403 } });
    await vi.advanceTimersByTimeAsync(3000);
    const calls = api.status.mock.calls.length;
    await vi.advanceTimersByTimeAsync(15000);
    expect(api.status).toHaveBeenCalledTimes(calls);
    expect(wrapper.find('[data-testid="pair"]').exists()).toBe(false);
    wrapper.unmount();
    await vi.advanceTimersByTimeAsync(15000);
    expect(api.status).toHaveBeenCalledTimes(calls);
  });
});
