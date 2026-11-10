import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import Panel from './BackofficeCompletionDossier.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  getters: null,
  api: { list: vi.fn(), seal: vi.fn(), download: vi.fn() },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('dashboard/api/crm/backofficeDossiers', () => ({ default: mocks.api }));
vi.mock('./useBackofficePresentation', () => ({
  useBackofficePresentation: () => ({ text: key => key, date: value => value }),
}));
const empty = {
  data: [],
  meta: { page: 1, pages: 1, total: 0 },
  candidate_digest: 'synthetic-digest',
  can_seal: true,
};
const sealed = {
  ...empty,
  can_seal: false,
  data: [
    {
      id: 8,
      number: 1,
      sealed_at: '2026-11-05',
      archive_sha256: 'a'.repeat(64),
      current: true,
      can_download: true,
    },
  ],
};
const render = () =>
  mount(Panel, { props: { record: { id: 5, status: 'completed' } } });
const button = (wrapper, key) =>
  wrapper.findAll('button').find(row => row.text() === key);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: 1 } });
  mocks.getters = reactive({
    getCurrentUser: { id: 3 },
    getCurrentRole: 'agent',
  });
  mocks.api.list.mockResolvedValue({ data: structuredClone(empty) });
});

it('loads only on demand and requires explicit confirmation of the exact candidate before sealing', async () => {
  const wrapper = render();
  expect(mocks.api.list).not.toHaveBeenCalled();
  await wrapper.get('button').trigger('click');
  await flushPromises();
  expect(button(wrapper, 'COMPLETION_DOSSIER.SEAL').element.disabled).toBe(
    true
  );
  expect(mocks.api.seal).not.toHaveBeenCalled();
  mocks.api.seal.mockResolvedValue({ data: { id: 8 } });
  mocks.api.list.mockResolvedValue({ data: structuredClone(sealed) });
  await wrapper.get('input').setValue(true);
  await button(wrapper, 'COMPLETION_DOSSIER.SEAL').trigger('click');
  await flushPromises();
  expect(mocks.api.seal).toHaveBeenCalledWith(
    1,
    5,
    empty.candidate_digest,
    expect.any(Object)
  );
  expect(wrapper.find('input').exists()).toBe(false);
  expect(wrapper.text()).toContain('COMPLETION_DOSSIER.CURRENT');
  wrapper.unmount();
});

it('uses server pagination and does not allow downloads blocked by a new security observation', async () => {
  mocks.api.list.mockResolvedValue({
    data: {
      ...sealed,
      meta: { page: 1, pages: 2, total: 11 },
      data: [{ ...sealed.data[0], can_download: false }],
    },
  });
  const wrapper = render();
  await wrapper.get('button').trigger('click');
  await flushPromises();
  expect(button(wrapper, 'COMPLETION_DOSSIER.DOWNLOAD').element.disabled).toBe(
    true
  );
  await button(wrapper, 'NEXT').trigger('click');
  await flushPromises();
  expect(mocks.api.list).toHaveBeenLastCalledWith(1, 5, 2, expect.any(Object));
  expect(mocks.api.download).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('clears results and ignores a stale response after an account or role change', async () => {
  let finish;
  mocks.api.list.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render();
  await wrapper.get('button').trigger('click');
  mocks.route.params.accountId = 2;
  await flushPromises();
  finish({ data: structuredClone(sealed) });
  await flushPromises();
  expect(wrapper.text()).not.toContain(sealed.data[0].archive_sha256);
  await wrapper.get('button').trigger('click');
  await flushPromises();
  await wrapper.get('input').setValue(true);
  mocks.getters.getCurrentRole = 'administrator';
  await flushPromises();
  expect(wrapper.find('input').exists()).toBe(false);
  wrapper.unmount();
});

it('does not retry a conflict or retain a confirmation for a changed candidate', async () => {
  const wrapper = render();
  await wrapper.get('button').trigger('click');
  await flushPromises();
  mocks.api.seal.mockRejectedValue({ response: { status: 409 } });
  await wrapper.get('input').setValue(true);
  await button(wrapper, 'COMPLETION_DOSSIER.SEAL').trigger('click');
  await flushPromises();
  expect(mocks.api.seal).toHaveBeenCalledTimes(1);
  expect(wrapper.find('input').exists()).toBe(false);
  expect(wrapper.get('[role="alert"]').text()).toBe('COMPLETION_DOSSIER.ERROR');
  wrapper.unmount();
});

it('downloads the selected sealed revision and releases the browser object URL', async () => {
  const create = vi.fn().mockReturnValue('blob:synthetic');
  const revoke = vi.fn();
  vi.stubGlobal('URL', { createObjectURL: create, revokeObjectURL: revoke });
  const click = vi
    .spyOn(HTMLAnchorElement.prototype, 'click')
    .mockImplementation(() => {});
  mocks.api.list.mockResolvedValue({ data: structuredClone(sealed) });
  mocks.api.download.mockResolvedValue({
    data: new Blob(['synthetic sealed archive']),
  });
  const wrapper = render();
  await wrapper.get('button').trigger('click');
  await flushPromises();
  await button(wrapper, 'COMPLETION_DOSSIER.DOWNLOAD').trigger('click');
  await flushPromises();
  expect(mocks.api.download).toHaveBeenCalledWith(1, 5, 8, expect.any(Object));
  expect(click).toHaveBeenCalledOnce();
  expect(revoke).toHaveBeenCalledWith('blob:synthetic');
  wrapper.unmount();
  click.mockRestore();
  vi.unstubAllGlobals();
});
