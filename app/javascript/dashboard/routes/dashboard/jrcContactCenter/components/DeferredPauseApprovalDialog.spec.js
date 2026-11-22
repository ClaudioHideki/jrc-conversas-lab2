import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import DeferredPauseDialog from './DeferredPauseDialog.vue';
import { pausePreviewData } from '../helpers/pauseApprovalPreview.fixtures';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    requestDeferredPause: vi.fn(),
    cancelDeferredPause: vi.fn(),
    previewPauseApproval: vi.fn(),
    applyApprovedPause: vi.fn(),
  },
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
const props = {
  accountId: '1',
  memberId: '2',
  contextKey: 'SYNTHETIC:1',
  stateVersion: '7',
  requestRevision: 'a'.repeat(64),
  reasonCode: 'synthetic_break',
  reasonLabel: 'SYNTHETIC private reason',
  queueId: '50',
  justification: 'SYNTHETIC private review',
  approvalRequired: true,
};
const receipt = (id, state = 'pending') => ({
  data: {
    account_id: '1',
    item: {
      account_user_id: '2',
      state: 'available',
      state_version: '7',
      pause_request_revision: 'c'.repeat(64),
      provider_confirmed: false,
    },
    receipt: { request_id: id, state },
  },
});
beforeEach(() => {
  vi.resetAllMocks();
  API.previewPauseApproval.mockImplementation((_, values) =>
    Promise.resolve({ data: pausePreviewData(values) })
  );
  API.requestDeferredPause.mockImplementation((_, values) =>
    Promise.resolve(receipt(values.command_id))
  );
  API.applyApprovedPause.mockImplementation((_, id) =>
    Promise.resolve(receipt(id, 'applied'))
  );
});

describe('native pause approval dialog (HTTP mocked, not a persistence proof)', () => {
  it('loads the complete impact but makes no approval or pause until explicit confirmation', async () => {
    const wrapper = mount(DeferredPauseDialog, { props });
    await flushPromises();
    expect(wrapper.text()).toContain('SYNTHETIC unidade A');
    expect(wrapper.text()).toContain('SYNTHETIC unidade B');
    expect(API.previewPauseApproval).toHaveBeenCalledOnce();
    expect(API.requestDeferredPause).not.toHaveBeenCalled();
    expect(wrapper.emitted('updated')).toBeUndefined();
  });

  it('submits the exact reviewed request with a separate impact digest and no client scope grants', async () => {
    const wrapper = mount(DeferredPauseDialog, { props });
    await flushPromises();
    const values = API.previewPauseApproval.mock.calls[0][1];
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await flushPromises();
    expect(API.requestDeferredPause).toHaveBeenCalledWith(
      '1',
      values,
      'b'.repeat(64)
    );
    expect(Object.keys(values).sort()).toEqual([
      'command_id',
      'expected_request_revision',
      'expected_state_version',
      'justification',
      'queue_id',
      'reason_code',
    ]);
    expect(wrapper.emitted('updated')).toHaveLength(1);
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('blocks confirmation while the impact is still loading', async () => {
    API.previewPauseApproval.mockReturnValueOnce(new Promise(() => {}));
    const wrapper = mount(DeferredPauseDialog, { props });
    await flushPromises();
    expect(
      wrapper.get('[data-deferred-pause-confirm]').attributes('disabled')
    ).toBeDefined();
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    expect(API.requestDeferredPause).not.toHaveBeenCalled();
  });

  it('discards an old impact arriving after an account or profile context change', async () => {
    let finish;
    API.previewPauseApproval.mockImplementationOnce(
      (_, values) =>
        new Promise(resolve => {
          finish = () => resolve({ data: pausePreviewData(values) });
        })
    );
    const wrapper = mount(DeferredPauseDialog, { props });
    await wrapper.setProps({ accountId: '9', contextKey: 'SYNTHETIC:9' });
    finish();
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC unidade A');
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(API.requestDeferredPause).not.toHaveBeenCalled();
  });

  it('clears private text and scope details after an authenticated denial', async () => {
    API.previewPauseApproval.mockRejectedValueOnce({
      response: { status: 403 },
    });
    const wrapper = mount(DeferredPauseDialog, { props });
    await flushPromises();
    expect(wrapper.text()).not.toContain(props.justification);
    expect(wrapper.text()).not.toContain('SYNTHETIC unidade A');
    expect(wrapper.emitted('denied')).toHaveLength(1);
    expect(wrapper.find('[data-deferred-pause-confirm]').exists()).toBe(false);
    expect(API.requestDeferredPause).not.toHaveBeenCalled();
  });

  it('offers an explicit read-only preview retry with the same native request identity', async () => {
    API.previewPauseApproval.mockRejectedValueOnce(
      new Error('SYNTHETIC unavailable')
    );
    const wrapper = mount(DeferredPauseDialog, { props });
    await flushPromises();
    const first = API.previewPauseApproval.mock.calls[0][1];
    expect(API.previewPauseApproval).toHaveBeenCalledOnce();
    await wrapper.get('[data-pause-approval-preview-retry]').trigger('click');
    await flushPromises();
    expect(API.previewPauseApproval.mock.calls[1]).toEqual(['1', first]);
    expect(wrapper.text()).toContain('SYNTHETIC unidade B');
    expect(API.requestDeferredPause).not.toHaveBeenCalled();
  });

  it('rejects a cross-account response instead of allowing a confirmation', async () => {
    API.previewPauseApproval.mockImplementationOnce((_, values) =>
      Promise.resolve({
        data: { ...pausePreviewData(values), account_id: '9' },
      })
    );
    const wrapper = mount(DeferredPauseDialog, { props });
    await flushPromises();
    expect(
      wrapper.get('[data-deferred-pause-confirm]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.text()).not.toContain('SYNTHETIC unidade A');
    expect(API.requestDeferredPause).not.toHaveBeenCalled();
  });

  it('applies only the owned pending UUID and fresh state version through the existing native pause API', async () => {
    const id = '00000000-0000-4000-8000-000000000099';
    const wrapper = mount(DeferredPauseDialog, {
      props: {
        ...props,
        mode: 'apply',
        requestId: id,
        approvalRequired: false,
      },
    });
    await flushPromises();
    expect(API.applyApprovedPause).not.toHaveBeenCalled();
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await flushPromises();
    expect(API.applyApprovedPause).toHaveBeenCalledWith('1', id, '7');
    expect(API.requestDeferredPause).not.toHaveBeenCalled();
    expect(API.previewPauseApproval).not.toHaveBeenCalled();
    expect(wrapper.emitted('updated')).toHaveLength(1);
  });

  it('does not close silently when the native apply response reports a blocked request', async () => {
    API.applyApprovedPause.mockImplementationOnce((_, id) =>
      Promise.resolve(receipt(id, 'blocked'))
    );
    const wrapper = mount(DeferredPauseDialog, {
      props: {
        ...props,
        mode: 'apply',
        requestId: 'owned-id',
        approvalRequired: false,
      },
    });
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.DEFERRED_PAUSE.BLOCKED'
    );
    expect(wrapper.emitted('close')).toBeUndefined();
    expect(API.applyApprovedPause).toHaveBeenCalledOnce();
  });

  it('retries an uncertain creation only after confirmation using exactly the same request and impact digest', async () => {
    API.requestDeferredPause.mockRejectedValueOnce(
      new Error('SYNTHETIC response lost')
    );
    const wrapper = mount(DeferredPauseDialog, { props });
    await flushPromises();
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await flushPromises();
    const original = API.requestDeferredPause.mock.calls[0];
    expect(API.requestDeferredPause).toHaveBeenCalledOnce();
    await wrapper.get('[data-deferred-pause-confirm]').trigger('click');
    await flushPromises();
    expect(API.requestDeferredPause.mock.calls[1]).toEqual(original);
    expect(API.previewPauseApproval).toHaveBeenCalledOnce();
  });
});
