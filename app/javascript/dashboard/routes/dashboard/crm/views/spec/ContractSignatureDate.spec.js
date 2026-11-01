import { mount, flushPromises } from '@vue/test-utils';
import ContractsView from '../contracts/ContractsView.vue';

const mocks = vi.hoisted(() => ({ list: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/api/crm/commercialCycle', () => ({ contractsAPI: mocks }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/routes/dashboard/approvals/ApprovalGateBadge.vue', () => ({
  default: { template: '<div />' },
}));

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

it('prefills the signature time as local time rather than a future UTC time in São Paulo', async () => {
  vi.stubEnv('TZ', 'America/Sao_Paulo');
  vi.useFakeTimers({ toFake: ['Date'] });
  const instant = new Date('2026-11-01T16:30:00Z');
  vi.setSystemTime(instant);
  mocks.list.mockResolvedValue({
    data: [
      {
        id: 1,
        contract_number: 'CTR-1',
        status: 'awaiting_signature',
        signature_status: 'prepared',
        starts_on: '2026-11-01',
        ends_on: '2027-11-01',
        owner: { id: 1, name: 'Operator' },
      },
    ],
  });
  const wrapper = mount(ContractsView, {
    global: { stubs: { Teleport: true, RouterLink: true, FluentIcon: true } },
  });
  await flushPromises();
  await wrapper.get('button[title="Gerenciar assinatura"]').trigger('click');
  const value = wrapper.get('input[type="datetime-local"]').element.value;
  wrapper.unmount();
  expect(value).toBe('2026-11-01T13:30');
  expect(new Date(value).getTime()).toBe(instant.getTime());
});
