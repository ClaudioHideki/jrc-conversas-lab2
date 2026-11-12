import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import Report from './BackofficeCompletionReport.vue';
const mocks = vi.hoisted(() => ({
  api: vi.fn(),
  route: null,
  create: vi.fn(),
  revoke: vi.fn(),
  click: vi.fn(),
}));
vi.mock('dashboard/api/crm/commercialCycle', () => ({
  backofficeAPI: { completionReport: mocks.api },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
beforeEach(() => {
  mocks.route = reactive({ params: { accountId: 1 } });
  mocks.create.mockReturnValue('blob:synthetic-local-report');
  vi.stubGlobal('URL', {
    createObjectURL: mocks.create,
    revokeObjectURL: mocks.revoke,
  });
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(
    mocks.click
  );
});
describe('Backoffice completion report download', () => {
  it('downloads only after the API returns and releases the local blob URL', async () => {
    mocks.api.mockResolvedValue({ data: new Blob(['Synthetic CSV']) });
    const wrapper = mount(Report, {
      props: { record: { id: 12, status: 'completed' } },
    });
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(mocks.api).toHaveBeenCalledWith(1, 12);
    expect(mocks.click).toHaveBeenCalledOnce();
    expect(mocks.revoke).toHaveBeenCalledWith('blob:synthetic-local-report');
    wrapper.unmount();
  });
  it('does not expose a completion action on an active request', () => {
    const wrapper = mount(Report, {
      props: { record: { id: 12, status: 'in_progress' } },
    });
    expect(wrapper.find('button').exists()).toBe(false);
    expect(mocks.api).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('reports access failure without downloading or claiming success', async () => {
    mocks.api.mockRejectedValue({ response: { status: 403 } });
    const wrapper = mount(Report, {
      props: { record: { id: 12, status: 'completed' } },
    });
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(mocks.create).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it.each(['account', 'unmount'])(
    'discards a late response after %s changes',
    async change => {
      let resolve;
      mocks.api.mockImplementation(
        () =>
          new Promise(done => {
            resolve = done;
          })
      );
      const wrapper = mount(Report, {
        props: { record: { id: 12, status: 'completed' } },
      });
      await wrapper.get('button').trigger('click');
      if (change === 'account') mocks.route.params.accountId = 2;
      else wrapper.unmount();
      await flushPromises();
      resolve({ data: new Blob(['Old account data']) });
      await flushPromises();
      expect(mocks.create).not.toHaveBeenCalled();
      if (change === 'account') wrapper.unmount();
    }
  );
});
