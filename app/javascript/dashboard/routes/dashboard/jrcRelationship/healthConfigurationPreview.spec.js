import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, expect, it, vi } from 'vitest';
import Component from './HealthConfigurationPreview.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  portfolio: vi.fn(),
  previewHealthConfiguration: vi.fn(),
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => mocks.store }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const configuration = () => ({
  scope_key: 'account',
  version: 7,
  weights: { adoption: 100 },
  rules: { missing_factor_policy: 'renormalize' },
});
const result = {
  simulation: true,
  business_writes_performed: false,
  draft_effective: true,
  customer: { id: 9, name: 'Synthetic visible customer' },
  current: {
    scope_key: 'account',
    version: 7,
    health: { score: 50, band: 'risk', factors: [] },
  },
  proposed: {
    scope_key: 'account',
    version: 8,
    health: { score: 100, band: 'healthy', factors: [] },
  },
};
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1' } });
  mocks.store = {
    getters: reactive({ getCurrentUserID: 2, getCurrentRole: 'administrator' }),
  };
  mocks.portfolio.mockResolvedValue({
    data: {
      payload: [{ id: 9, name: 'Synthetic visible customer' }],
      meta: { page: 1, per_page: 10, total: 20 },
    },
  });
  mocks.previewHealthConfiguration.mockResolvedValue({ data: result });
});
it('uses scoped paginated native customers and only the read-only preview endpoint, invalidating the result after a draft edit', async () => {
  const draft = configuration();
  const wrapper = mount(Component, { props: { configuration: draft } });
  expect(mocks.portfolio).not.toHaveBeenCalled();
  await wrapper.get('[data-testid="health-preview-find"]').trigger('click');
  await flushPromises();
  expect(mocks.portfolio).toHaveBeenCalledWith(
    '1',
    { q: '', page: 1, per_page: 10 },
    expect.anything()
  );
  await wrapper.get('[data-testid="health-preview-customer"]').setValue('9');
  await wrapper.get('[data-testid="health-preview-run"]').trigger('click');
  await flushPromises();
  expect(mocks.previewHealthConfiguration).toHaveBeenCalledWith(
    '1',
    { ...draft, assignment_id: 9 },
    expect.anything()
  );
  expect(
    wrapper.get('[data-testid="health-preview-current"]').text()
  ).toContain('50');
  expect(
    wrapper.get('[data-testid="health-preview-proposed"]').text()
  ).toContain('100');
  await wrapper.setProps({
    configuration: { ...draft, weights: { relationship: 100 } },
  });
  expect(wrapper.find('[data-testid="health-preview-proposed"]').exists()).toBe(
    false
  );
  wrapper.unmount();
});
it('keeps native scope precedence visible and pages after a selected customer without retaining the previous result', async () => {
  mocks.previewHealthConfiguration.mockResolvedValue({
    data: { ...result, draft_effective: false },
  });
  const wrapper = mount(Component, {
    props: { configuration: configuration() },
  });
  await wrapper.get('[data-testid="health-preview-find"]').trigger('click');
  await flushPromises();
  await wrapper.get('[data-testid="health-preview-customer"]').setValue('9');
  await wrapper.get('[data-testid="health-preview-run"]').trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain('RELATIONSHIP.HEALTH_PREVIEW.PRECEDENCE');
  await wrapper.get('[data-testid="health-preview-next"]').trigger('click');
  await flushPromises();
  expect(mocks.portfolio.mock.calls.at(-1)[1]).toEqual({
    q: '',
    page: 2,
    per_page: 10,
  });
  expect(wrapper.find('[data-testid="health-preview-proposed"]').exists()).toBe(
    false
  );
  expect(wrapper.find('[data-testid="health-preview-customer"]').exists()).toBe(
    true
  );
  wrapper.unmount();
});
it('aborts identity changes and never displays a late response from the prior account', async () => {
  let complete;
  mocks.previewHealthConfiguration.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        complete = resolve;
      })
  );
  const wrapper = mount(Component, {
    props: { configuration: configuration() },
  });
  await wrapper.get('[data-testid="health-preview-find"]').trigger('click');
  await flushPromises();
  await wrapper.get('[data-testid="health-preview-customer"]').setValue('9');
  await wrapper.get('[data-testid="health-preview-run"]').trigger('click');
  const request = mocks.previewHealthConfiguration.mock.calls[0][2];
  mocks.route.params.accountId = '2';
  await flushPromises();
  complete({ data: result });
  await flushPromises();
  expect(request.signal.aborted).toBe(true);
  expect(wrapper.text()).not.toContain('Synthetic visible customer');
  expect(wrapper.find('[data-testid="health-preview-proposed"]').exists()).toBe(
    false
  );
  wrapper.unmount();
});
it('clears scoped labels after access denial and never reports a saved configuration', async () => {
  mocks.previewHealthConfiguration.mockRejectedValue({
    response: { status: 403, data: { errors: ['Permission revoked'] } },
  });
  const wrapper = mount(Component, {
    props: { configuration: configuration() },
  });
  await wrapper.get('[data-testid="health-preview-find"]').trigger('click');
  await flushPromises();
  await wrapper.get('[data-testid="health-preview-customer"]').setValue('9');
  await wrapper.get('[data-testid="health-preview-run"]').trigger('click');
  await flushPromises();
  expect(wrapper.text()).not.toContain('Synthetic visible customer');
  expect(wrapper.find('[role="alert"]').text()).toContain('Permission revoked');
  expect(wrapper.emitted('save')).toBeUndefined();
  expect(wrapper.find('[data-testid="health-preview-proposed"]').exists()).toBe(
    false
  );
  wrapper.unmount();
});
