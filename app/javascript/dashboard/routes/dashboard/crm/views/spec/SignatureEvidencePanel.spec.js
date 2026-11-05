import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import Panel from '../backoffice/SignatureEvidencePanel.vue';

const mocks = vi.hoisted(() => ({
  getters: {},
  api: {
    evidence: vi.fn(),
    captureEvidence: vi.fn(),
    acceptEvidence: vi.fn(),
    downloadEvidence: vi.fn(),
  },
}));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('dashboard/api/crm/backofficeSignatures', () => ({
  default: mocks.api,
}));
vi.mock('../backoffice/useBackofficePresentation', () => ({
  useBackofficePresentation: () => ({ text: key => key }),
}));
const state = {
  state: 'verified',
  source_digest: 'synthetic-source-digest',
  version_number: 2,
  accepted: false,
  can_capture: false,
  can_accept: true,
  downloads: [
    { kind: 'signed_document', available: true },
    { kind: 'certificate', available: false },
  ],
};
const render = () =>
  mount(Panel, { props: { accountId: 1, requestId: 9, deliveryId: 8 } });
const button = (wrapper, name) =>
  wrapper
    .findAll('button')
    .find(row => row.text() === `SIGNATURE_EVIDENCE.${name}`);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.getters = reactive({
    getCurrentUser: { id: 3 },
    getCurrentRole: 'agent',
  });
  mocks.api.evidence.mockResolvedValue({ data: structuredClone(state) });
});

it('loads only persisted status and never captures or accepts automatically', async () => {
  const wrapper = render();
  await flushPromises();
  expect(mocks.api.evidence).toHaveBeenCalledWith(
    1,
    9,
    8,
    expect.objectContaining({ signal: expect.any(AbortSignal) })
  );
  expect(mocks.api.captureEvidence).not.toHaveBeenCalled();
  expect(mocks.api.acceptEvidence).not.toHaveBeenCalled();
  expect(button(wrapper, 'ACCEPT').element.disabled).toBe(true);
  expect(button(wrapper, 'FILES.certificate').element.disabled).toBe(true);
  wrapper.unmount();
});

it('requires confirmation and sends the exact current receipt digest once', async () => {
  mocks.api.acceptEvidence.mockResolvedValue({
    data: { ...state, accepted: true, can_accept: false },
  });
  const wrapper = render();
  await flushPromises();
  await wrapper.find('input').setValue(true);
  await button(wrapper, 'ACCEPT').trigger('click');
  await flushPromises();
  expect(mocks.api.acceptEvidence).toHaveBeenCalledWith(
    1,
    9,
    8,
    state.source_digest,
    expect.any(Object)
  );
  expect(wrapper.emitted('updated')).toHaveLength(1);
  expect(wrapper.find('input').exists()).toBe(false);
  expect(wrapper.text()).toContain('SIGNATURE_EVIDENCE.ACCEPTED');
  wrapper.unmount();
});

it('retrieves provider files only on the explicit authorized capture action', async () => {
  mocks.api.evidence.mockResolvedValue({
    data: {
      ...state,
      state: 'not_received',
      can_capture: true,
      can_accept: false,
      downloads: [],
    },
  });
  mocks.api.captureEvidence.mockResolvedValue({
    data: { ...state, state: 'pending', can_accept: false },
  });
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'CAPTURE').trigger('click');
  await flushPromises();
  expect(mocks.api.captureEvidence).toHaveBeenCalledTimes(1);
  expect(wrapper.text()).toContain('SIGNATURE_EVIDENCE.PENDING');
  expect(mocks.api.acceptEvidence).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('clears cached evidence and propagates a revoked permission', async () => {
  const wrapper = render();
  await flushPromises();
  mocks.api.evidence.mockRejectedValue({ response: { status: 403 } });
  await button(wrapper, 'REFRESH').trigger('click');
  await flushPromises();
  expect(wrapper.emitted('denied')).toHaveLength(1);
  expect(wrapper.find('input').exists()).toBe(false);
  expect(wrapper.text()).not.toContain('SIGNATURE_EVIDENCE.VERIFIED');
  wrapper.unmount();
});

it('ignores a stale account response and resets confirmation on identity changes', async () => {
  let finish;
  mocks.api.evidence.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render();
  await wrapper.setProps({ accountId: 2 });
  await flushPromises();
  finish({ data: { ...state, state: 'invalid', can_accept: false } });
  await flushPromises();
  expect(wrapper.text()).toContain('SIGNATURE_EVIDENCE.VERIFIED');
  await wrapper.find('input').setValue(true);
  mocks.getters.getCurrentRole = 'administrator';
  await flushPromises();
  expect(wrapper.find('input').element.checked).toBe(false);
  wrapper.unmount();
});

it('downloads only an enabled scoped PDF and revokes the temporary object URL', async () => {
  const create = vi.fn().mockReturnValue('blob:synthetic');
  const revoke = vi.fn();
  vi.stubGlobal('URL', { createObjectURL: create, revokeObjectURL: revoke });
  const click = vi
    .spyOn(HTMLAnchorElement.prototype, 'click')
    .mockImplementation(() => {});
  mocks.api.downloadEvidence.mockResolvedValue({
    data: new Blob(['synthetic PDF']),
  });
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'FILES.signed_document').trigger('click');
  await flushPromises();
  expect(mocks.api.downloadEvidence).toHaveBeenCalledWith(
    1,
    9,
    8,
    'signed_document',
    expect.any(Object)
  );
  expect(click).toHaveBeenCalledOnce();
  expect(revoke).toHaveBeenCalledWith('blob:synthetic');
  wrapper.unmount();
  vi.unstubAllGlobals();
  click.mockRestore();
});
