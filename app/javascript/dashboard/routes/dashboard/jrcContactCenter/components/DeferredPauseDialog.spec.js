import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import DeferredPauseDialog from './DeferredPauseDialog.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { requestDeferredPause: vi.fn(), cancelDeferredPause: vi.fn() },
}));
vi.mock('dashboard/components-next/dialog/Dialog.vue', () => ({
  default: {
    emits: ['close'],
    setup(_, { expose, emit }) {
      expose({ open: vi.fn(), close: () => emit('close') });
    },
    template: '<section><slot /><slot name="footer" /></section>',
  },
}));
enableAutoUnmount(afterEach);
const requestId = '00000000-0000-4000-8000-000000000019';
const props = {
  accountId: '1',
  memberId: '2',
  contextKey: 'SYNTHETIC:1',
  stateVersion: '7',
  requestRevision: 'a'.repeat(64),
  reasonCode: 'synthetic_break',
  reasonLabel: 'SYNTHETIC private reason',
  queueId: '3',
  justification: 'SYNTHETIC private text',
};
const receipt = (id, state = 'pending') => ({
  data: {
    account_id: '1',
    item: {
      account_user_id: '2',
      state: 'acw',
      state_version: '7',
      pause_request_revision: 'b'.repeat(64),
      provider_confirmed: false,
    },
    receipt: { request_id: id, state },
  },
});

beforeEach(() => {
  vi.resetAllMocks();
  API.requestDeferredPause.mockImplementation((_, values) =>
    Promise.resolve(receipt(values.command_id))
  );
  API.cancelDeferredPause.mockImplementation((_, id) =>
    Promise.resolve(receipt(id, 'cancelled'))
  );
});

describe('deferred pause review UI (mocked presentation tests, not persistence evidence)', () => {
  it('opens a review without sending or changing the state until explicit confirmation', async () => {
    const wrapper = mount(DeferredPauseDialog, { props });
    await flushPromises();
    expect(wrapper.text()).toContain(props.reasonLabel);
    expect(wrapper.text()).toContain(props.justification);
    expect(API.requestDeferredPause).not.toHaveBeenCalled();
    expect(wrapper.emitted('updated')).toBeUndefined();
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await flushPromises();
    expect(API.requestDeferredPause).toHaveBeenCalledOnce();
    expect(API.requestDeferredPause).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({
        command_id: expect.any(String),
        reason_code: props.reasonCode,
        queue_id: '3',
        justification: props.justification,
        expected_state_version: '7',
        expected_request_revision: 'a'.repeat(64),
      })
    );
    expect(wrapper.emitted('updated')).toHaveLength(1);
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('does not issue a second request while the first explicit confirmation is still pending', async () => {
    let resolve;
    API.requestDeferredPause.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = mount(DeferredPauseDialog, { props });
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    expect(API.requestDeferredPause).toHaveBeenCalledOnce();
    expect(
      wrapper.get('[data-deferred-pause-close]').attributes('disabled')
    ).toBeDefined();
    const values = API.requestDeferredPause.mock.calls[0][1];
    resolve(receipt(values.command_id));
    await flushPromises();
    expect(wrapper.emitted('updated')).toHaveLength(1);
  });

  it('locks an uncertain result and retries only the same UUID, body, account and initial revision after another explicit click', async () => {
    API.requestDeferredPause.mockRejectedValueOnce(
      new Error('SYNTHETIC lost response')
    );
    const wrapper = mount(DeferredPauseDialog, { props });
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await flushPromises();
    const first = API.requestDeferredPause.mock.calls[0][1];
    expect(wrapper.find('[data-deferred-pause-uncertain]').exists()).toBe(true);
    expect(wrapper.emitted('updated')).toBeUndefined();
    await wrapper.setProps({
      reasonCode: 'changed',
      justification: 'changed',
      stateVersion: '99',
      requestRevision: 'c'.repeat(64),
    });
    expect(API.requestDeferredPause).toHaveBeenCalledOnce();
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await flushPromises();
    expect(API.requestDeferredPause.mock.calls[1]).toEqual(['1', first]);
    expect(first).toMatchObject({
      reason_code: props.reasonCode,
      justification: props.justification,
      expected_state_version: '7',
      expected_request_revision: 'a'.repeat(64),
    });
    expect(wrapper.emitted('updated')).toHaveLength(1);
  });

  it('does not treat HTTP200 without a verified receipt as confirmation', async () => {
    const response = receipt(requestId);
    delete response.data.receipt;
    API.requestDeferredPause.mockResolvedValueOnce(response);
    const wrapper = mount(DeferredPauseDialog, { props });
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-deferred-pause-uncertain]').exists()).toBe(true);
    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(wrapper.emitted('close')).toBeUndefined();
  });

  it('does not accept a receipt without the authoritative request revision', async () => {
    API.requestDeferredPause.mockImplementationOnce((_, values) => {
      const response = receipt(values.command_id);
      delete response.data.item.pause_request_revision;
      return Promise.resolve(response);
    });
    const wrapper = mount(DeferredPauseDialog, { props });
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-deferred-pause-uncertain]').exists()).toBe(true);
    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(wrapper.emitted('close')).toBeUndefined();
  });

  ['account_id', 'member_id', 'request_id'].forEach(identity => {
    it(`rejects a response whose ${identity} does not match the reviewed operation`, async () => {
      API.requestDeferredPause.mockImplementationOnce((_, values) => {
        const response = receipt(values.command_id);
        if (identity === 'account_id') response.data.account_id = '99';
        if (identity === 'member_id') response.data.item.account_user_id = '99';
        if (identity === 'request_id')
          response.data.receipt.request_id = 'invalid';
        return Promise.resolve(response);
      });
      const wrapper = mount(DeferredPauseDialog, { props });
      await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
      await flushPromises();
      expect(wrapper.find('[data-deferred-pause-uncertain]').exists()).toBe(
        true
      );
      expect(wrapper.emitted('updated')).toBeUndefined();
    });
  });

  [401, 403].forEach(status => {
    it(`clears private review text and stops requests after authority denial ${status}`, async () => {
      API.requestDeferredPause.mockRejectedValueOnce({ response: { status } });
      const wrapper = mount(DeferredPauseDialog, { props });
      await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
      await flushPromises();
      expect(wrapper.text()).not.toContain(props.justification);
      expect(wrapper.text()).not.toContain(props.reasonLabel);
      expect(wrapper.find('[data-deferred-pause-confirm]').exists()).toBe(
        false
      );
      expect(wrapper.emitted('denied')).toHaveLength(1);
      expect(wrapper.emitted('updated')).toBeUndefined();
    });
  });

  it('preserves a known rejected draft for review without retrying or claiming success', async () => {
    API.requestDeferredPause.mockRejectedValueOnce({
      response: { status: 409, data: { error: 'state_conflict' } },
    });
    const wrapper = mount(DeferredPauseDialog, { props });
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(props.justification);
    expect(wrapper.find('[data-deferred-pause-confirm]').exists()).toBe(false);
    expect(wrapper.find('[data-deferred-pause-uncertain]').exists()).toBe(
      false
    );
    expect(wrapper.emitted('updated')).toBeUndefined();
    await wrapper.get('[data-deferred-pause-close]').trigger('click');
    expect(wrapper.emitted('refresh')).toHaveLength(1);
    expect(API.requestDeferredPause).toHaveBeenCalledOnce();
  });

  it('requires an explicit second close review before abandoning an uncertain result and checking native state', async () => {
    API.requestDeferredPause.mockRejectedValueOnce(
      new Error('SYNTHETIC lost response')
    );
    const wrapper = mount(DeferredPauseDialog, { props });
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-deferred-pause-close]').trigger('click');
    expect(wrapper.find('[data-deferred-pause-close-review]').exists()).toBe(
      true
    );
    expect(wrapper.emitted('refresh')).toBeUndefined();
    await wrapper.get('[data-deferred-pause-close]').trigger('click');
    expect(wrapper.emitted('refresh')).toHaveLength(1);
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(API.requestDeferredPause).toHaveBeenCalledOnce();
  });

  ['accountId', 'memberId'].forEach(field => {
    it(`ignores a late result after ${field} changes and clears the previous private review`, async () => {
      let resolve;
      API.requestDeferredPause.mockImplementationOnce(
        () =>
          new Promise(done => {
            resolve = done;
          })
      );
      const wrapper = mount(DeferredPauseDialog, { props });
      await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
      const values = API.requestDeferredPause.mock.calls[0][1];
      await wrapper.setProps({ [field]: '99' });
      resolve(receipt(values.command_id));
      await flushPromises();
      expect(wrapper.emitted('updated')).toBeUndefined();
      expect(wrapper.text()).not.toContain(props.justification);
      expect(wrapper.emitted('close')).toHaveLength(1);
    });
  });

  it('cancels only the identified request after explicit review instead of issuing a native unpause', async () => {
    const wrapper = mount(DeferredPauseDialog, {
      props: { ...props, mode: 'cancel', requestId },
    });
    expect(API.cancelDeferredPause).not.toHaveBeenCalled();
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await flushPromises();
    expect(API.cancelDeferredPause).toHaveBeenCalledWith('1', requestId);
    expect(API.requestDeferredPause).not.toHaveBeenCalled();
    expect(wrapper.emitted('updated')).toHaveLength(1);
  });

  it('does not represent an already applied request as successfully cancelled', async () => {
    API.cancelDeferredPause.mockRejectedValueOnce({
      response: { status: 409, data: { error: 'pause_already_applied' } },
    });
    const wrapper = mount(DeferredPauseDialog, {
      props: { ...props, mode: 'cancel', requestId },
    });
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.DEFERRED_PAUSE.ALREADY_APPLIED'
    );
    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(wrapper.find('[data-deferred-pause-confirm]').exists()).toBe(false);
  });

  it('keeps a blocked receipt visible for review and never presents it as a started pause', async () => {
    API.requestDeferredPause.mockImplementationOnce((_, values) =>
      Promise.resolve(receipt(values.command_id, 'blocked'))
    );
    const wrapper = mount(DeferredPauseDialog, { props });
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.DEFERRED_PAUSE.BLOCKED'
    );
    expect(wrapper.emitted('updated')).toHaveLength(1);
    expect(wrapper.emitted('close')).toBeUndefined();
    expect(wrapper.find('[data-deferred-pause-confirm]').exists()).toBe(false);
  });
});
