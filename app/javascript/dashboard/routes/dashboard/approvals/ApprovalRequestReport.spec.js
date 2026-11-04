import { flushPromises, mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import Report from './ApprovalRequestReport.vue';

const mocks = vi.hoisted(() => ({
  client: vi.fn(),
  report: vi.fn(),
  create: vi.fn(),
  revoke: vi.fn(),
  click: vi.fn(),
}));
vi.mock('dashboard/api/approvals', () => ({ approvalClient: mocks.client }));
const props = () => ({
  request: { id: 9, lock_version: 2 },
  context: { account_id: 1, member_id: 4 },
});
beforeEach(() => {
  mocks.client.mockReturnValue({ report: mocks.report });
  mocks.report.mockResolvedValue({
    data: new Blob(['Synthetic native report']),
  });
  mocks.create.mockReturnValue('blob:synthetic-approval-report');
  vi.stubGlobal('URL', {
    createObjectURL: mocks.create,
    revokeObjectURL: mocks.revoke,
  });
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(
    mocks.click
  );
});
describe('Native approval report download', () => {
  it('uses the explicit account and releases the download URL after the server responds', async () => {
    const wrapper = mount(Report, { props: props() });
    expect(mocks.report).not.toHaveBeenCalled();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(mocks.client).toHaveBeenCalledWith(1);
    expect(mocks.report).toHaveBeenCalledWith(9);
    expect(mocks.click).toHaveBeenCalledOnce();
    expect(mocks.revoke).toHaveBeenCalledWith('blob:synthetic-approval-report');
    wrapper.unmount();
  });
  it('reports revoked access without downloading', async () => {
    mocks.report.mockRejectedValue({ response: { status: 403 } });
    const wrapper = mount(Report, { props: props() });
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(mocks.create).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it.each(['account', 'member', 'request', 'version', 'unmount'])(
    'ignores stale results after %s changes',
    async change => {
      let resolve;
      mocks.report.mockImplementation(
        () =>
          new Promise(done => {
            resolve = done;
          })
      );
      const wrapper = mount(Report, { props: props() });
      await wrapper.get('button').trigger('click');
      expect(wrapper.get('button').attributes('disabled')).toBeDefined();
      if (change === 'account')
        await wrapper.setProps({ context: { account_id: 2, member_id: 4 } });
      if (change === 'member')
        await wrapper.setProps({ context: { account_id: 1, member_id: 7 } });
      if (change === 'request')
        await wrapper.setProps({ request: { id: 10, lock_version: 2 } });
      if (change === 'version')
        await wrapper.setProps({ request: { id: 9, lock_version: 3 } });
      if (change === 'unmount') wrapper.unmount();
      await flushPromises();
      resolve({ data: new Blob(['Old scope']) });
      await flushPromises();
      expect(mocks.create).not.toHaveBeenCalled();
      if (change !== 'unmount') wrapper.unmount();
    }
  );
});
