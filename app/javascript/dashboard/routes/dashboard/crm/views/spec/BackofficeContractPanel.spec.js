import { reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Panel from '../backoffice/BackofficeContractPanel.vue';

const mocks = vi.hoisted(() => ({ route: null, replace: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
const render = () =>
  mount(Panel, {
    props: { record: { id: 9, contract: { id: 3 } } },
    global: {
      stubs: {
        BackofficeContractVersions: true,
        BackofficeContractSigners: true,
        BackofficeContractAuthority: true,
        BackofficeContractSignatures: true,
      },
    },
  });
beforeEach(() => {
  mocks.route = reactive({
    query: { tab: 'contracts', status: 'in_progress' },
  });
  mocks.replace.mockImplementation(async ({ query }) => {
    mocks.route.query = query;
  });
});

it('restores signature status and preserves its page and surrounding filters', async () => {
  mocks.route.query = {
    tab: 'contracts',
    contractTab: 'signature',
    signaturePage: '2',
    status: 'blocked',
  };
  const wrapper = render();
  expect(
    wrapper.findComponent({ name: 'BackofficeContractSignatures' }).exists()
  ).toBe(true);
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Versões e minuta')
    .trigger('click');
  await flushPromises();
  expect(mocks.route.query).toMatchObject({
    contractTab: 'versions',
    signaturePage: '2',
    status: 'blocked',
  });
  wrapper.unmount();
});

it('preserves the representation subtab when the panel remounts', async () => {
  const wrapper = render();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Representação e poderes')
    .trigger('click');
  await flushPromises();
  expect(mocks.route.query).toMatchObject({
    tab: 'contracts',
    contractTab: 'authority',
    status: 'in_progress',
  });
  expect(
    wrapper.findComponent({ name: 'BackofficeContractAuthority' }).exists()
  ).toBe(true);
  wrapper.unmount();
  const remounted = render();
  expect(
    remounted.findComponent({ name: 'BackofficeContractAuthority' }).exists()
  ).toBe(true);
  remounted.unmount();
});

it('preserves the signer subtab and surrounding query when the responsive layout remounts the panel', async () => {
  const wrapper = render();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Assinantes')
    .trigger('click');
  await flushPromises();
  expect(mocks.replace).toHaveBeenCalledWith({
    query: { tab: 'contracts', status: 'in_progress', contractTab: 'signers' },
  });
  expect(
    wrapper.findComponent({ name: 'BackofficeContractSigners' }).exists()
  ).toBe(true);
  wrapper.unmount();
  const remounted = render();
  expect(
    remounted.findComponent({ name: 'BackofficeContractSigners' }).exists()
  ).toBe(true);
  expect(
    remounted.findComponent({ name: 'BackofficeContractVersions' }).exists()
  ).toBe(false);
  remounted.unmount();
});

it('defaults unknown subtabs to versions and records the outer contract tab before navigation', async () => {
  mocks.route.query = { contractTab: 'unknown', status: 'blocked' };
  const wrapper = render();
  expect(
    wrapper.findComponent({ name: 'BackofficeContractVersions' }).exists()
  ).toBe(true);
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Assinantes')
    .trigger('click');
  await flushPromises();
  expect(mocks.replace).toHaveBeenCalledWith({
    query: { tab: 'contracts', status: 'blocked', contractTab: 'signers' },
  });
  wrapper.unmount();
});
