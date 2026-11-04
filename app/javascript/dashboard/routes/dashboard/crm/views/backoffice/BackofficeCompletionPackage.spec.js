import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import Package from './BackofficeCompletionPackage.vue';

const mocks = vi.hoisted(() => ({
  preview: vi.fn(),
  download: vi.fn(),
  route: null,
  create: vi.fn(),
  revoke: vi.fn(),
  click: vi.fn(),
}));
vi.mock('dashboard/api/crm/commercialCycle', () => ({
  backofficeAPI: {
    completionPackage: mocks.preview,
    downloadCompletionPackage: mocks.download,
  },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
const fixture = {
  coverage: 'incomplete',
  missing: [
    {
      kind: 'signed_contract',
      reason: 'VERSION_BOUND_SIGNED_ARTIFACT_UNAVAILABLE',
    },
  ],
  files: [
    {
      kind: 'document',
      id: 3,
      path: 'documents/3/v2',
      availability: 'blocked',
      sha256: 'a'.repeat(64),
    },
  ],
};
beforeEach(() => {
  mocks.route = reactive({ params: { accountId: 1 } });
  mocks.preview.mockResolvedValue({ data: fixture });
  mocks.download.mockResolvedValue({ data: new Blob(['Synthetic archive']) });
  mocks.create.mockReturnValue('blob:synthetic-package');
  vi.stubGlobal('URL', {
    createObjectURL: mocks.create,
    revokeObjectURL: mocks.revoke,
  });
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(
    mocks.click
  );
});
describe('Scoped documentary export', () => {
  it('loads an honest manifest before an explicit download and releases its blob URL', async () => {
    const wrapper = mount(Package, {
      props: { record: { id: 5, status: 'completed' } },
    });
    expect(mocks.preview).not.toHaveBeenCalled();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(mocks.preview).toHaveBeenCalledWith(1, 5);
    expect(wrapper.text()).toContain('Incomplete documentary coverage');
    expect(wrapper.text()).toContain('Blocked by document security checks');
    expect(mocks.download).not.toHaveBeenCalled();
    await wrapper.findAll('button').at(-1).trigger('click');
    await flushPromises();
    expect(mocks.download).toHaveBeenCalledWith(1, 5);
    expect(mocks.click).toHaveBeenCalledOnce();
    expect(mocks.revoke).toHaveBeenCalledWith('blob:synthetic-package');
    wrapper.unmount();
  });
  it('does not offer an export on an unfinished operation', () => {
    const wrapper = mount(Package, {
      props: { record: { id: 5, status: 'in_progress' } },
    });
    expect(wrapper.find('button').exists()).toBe(false);
    expect(mocks.preview).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('clears a manifest after access is revoked without claiming a successful download', async () => {
    const wrapper = mount(Package, {
      props: { record: { id: 5, status: 'completed' } },
    });
    await wrapper.get('button').trigger('click');
    await flushPromises();
    mocks.download.mockRejectedValue({ response: { status: 404 } });
    await wrapper.findAll('button').at(-1).trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(wrapper.find('ul').exists()).toBe(false);
    expect(mocks.create).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it.each(['account', 'request', 'reopen', 'unmount'])(
    'discards a late download after %s changes',
    async change => {
      const wrapper = mount(Package, {
        props: { record: { id: 5, status: 'completed' } },
      });
      await wrapper.get('button').trigger('click');
      await flushPromises();
      let resolve;
      mocks.download.mockImplementation(
        () =>
          new Promise(done => {
            resolve = done;
          })
      );
      await wrapper.findAll('button').at(-1).trigger('click');
      if (change === 'account') mocks.route.params.accountId = 2;
      if (change === 'request')
        await wrapper.setProps({ record: { id: 6, status: 'completed' } });
      if (change === 'reopen')
        await wrapper.setProps({ record: { id: 5, status: 'in_progress' } });
      if (change === 'unmount') wrapper.unmount();
      await flushPromises();
      resolve({ data: new Blob(['Old account']) });
      await flushPromises();
      expect(mocks.create).not.toHaveBeenCalled();
      if (change !== 'unmount') wrapper.unmount();
    }
  );
});
