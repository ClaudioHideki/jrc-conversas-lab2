import { mount, shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import messages from 'dashboard/i18n/locale/en/relationship.json';
import NativePanel from './ReviewedPortfolioBatchPanel.vue';
import GroupPanel from './PortfolioMembershipBatchPanel.vue';
import {
  validMasterAllocationReview,
  validMasterTransition,
} from './masterAllocationReviewReceipt';
import { validMembershipReview } from './portfolioMembershipReviewReceipt';
import { validOperationMetadata } from './reviewedOperationMetadata';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: {
    previewPortfolioBatch: vi.fn(),
    approvePortfolioBatch: vi.fn(),
    advancePortfolioBatch: vi.fn(),
    portfolioBatchReview: vi.fn(),
    portfolioGroup: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));
const proposal = {
  operation: 'master_allocation',
  ids: [11, 12],
  portfolio_group_id: 18,
  expected_version: 0,
  justification: 'Explicit native master review',
  request_id: 'b6617842-8401-44bf-a34a-8f1f90b623e6',
  creations: [{ company_id: 11, owner_id: 7 }],
};
const preview = {
  id: 91,
  revision: 1,
  digest: 'a'.repeat(64),
  state: 'previewed',
  inputs: proposal,
  summary: {
    portfolio_group_id: 18,
    portfolio_group_name: 'Synthetic native portfolio',
    create_count: 1,
    reuse_count: 1,
  },
  master_capacity: { state: 'not_configured', rows: [] },
  items: [11, 12].map((id, index) => ({
    company_id: id,
    assignment_id: null,
    mode: index ? 'reuse' : 'create',
    allocation: {
      owner_id: 7,
      team_id: null,
      business_unit_id: null,
      status: 'active',
      settings: {},
    },
    label: `Synthetic company ${id}`,
    state: 'pending',
    receipt: null,
    error_code: null,
  })),
};
const completed = {
  ...preview,
  state: 'completed',
  revision: 4,
  items: preview.items.map((item, index) => ({
    ...item,
    assignment_id: 31 + index,
    state: 'applied',
    receipt: {
      operation: 'master_allocation',
      updated: 1,
      company_id: item.company_id,
      assignment_id: 31 + index,
      assignment_digest: 'b'.repeat(64),
      allocation_state: index ? 'reused' : 'created',
      portfolio_group_id: 18,
      group_revision_before: index,
      group_version: index + 1,
      membership_state: 'linked',
    },
  })),
};
const group = { id: 18, version: 0, can_manage: true, status: 'active' };
const wrappers = [];
const render = (
  component = NativePanel,
  props = {
    accountId: '1400',
    actorId: 7,
    portfolioGroupId: 18,
    proposal,
  },
  shallow = false
) => {
  const wrapper = (shallow ? shallowMount : mount)(component, {
    props,
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
      stubs: { ReviewedCadencePanel: true, ReviewedOperationInventory: true },
    },
  });
  wrappers.push(wrapper);
  return wrapper;
};
beforeEach(() => {
  vi.resetAllMocks();
  sessionStorage.clear();
  mocks.route = reactive({ params: { accountId: '1400' } });
  mocks.store = reactive({
    getters: {
      getCurrentUserID: 7,
      getCurrentRole: 'administrator',
      getCurrentUser: { accounts: [] },
    },
  });
  mocks.api.previewPortfolioBatch.mockResolvedValue({
    data: structuredClone(preview),
  });
  mocks.api.approvePortfolioBatch.mockResolvedValue({
    data: { ...structuredClone(preview), revision: 2, state: 'running' },
  });
  mocks.api.advancePortfolioBatch.mockResolvedValue({
    data: structuredClone(completed),
  });
  mocks.api.portfolioGroup.mockResolvedValue({
    data: { ...group, version: 3 },
  });
});
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

it('uses a separate company subject receipt and retains the original allocation-only membership validator', () => {
  expect(validMasterAllocationReview(preview, 18, proposal)).toBe(true);
  expect(validMasterAllocationReview(completed, 18, proposal)).toBe(true);
  expect(validMembershipReview(preview, 18, proposal)).toBe(false);
  const changed = structuredClone(completed);
  changed.items[0].receipt.company_id = 12;
  expect(validMasterAllocationReview(changed, 18, proposal)).toBe(false);
  changed.items[0].receipt.company_id = 11;
  changed.items[1].receipt.group_revision_before = 0;
  expect(validMasterAllocationReview(changed, 18, proposal)).toBe(false);
});

it('rejects repointed company audiences, native creation attributes and assignment IDs before accepting a successful response', () => {
  const changed = structuredClone(preview);
  changed.inputs.creations[0].owner_id = 99;
  expect(validMasterAllocationReview(changed, 18, proposal)).toBe(false);
  changed.inputs = proposal;
  changed.items[0].assignment_id = 31;
  expect(validMasterAllocationReview(changed, 18, proposal)).toBe(false);
  changed.items[0].assignment_id = null;
  changed.inputs = { ...proposal, ids: [31, 32] };
  expect(validMasterAllocationReview(changed, 18, proposal)).toBe(false);
});

it('shows the create/reuse summary and requires explicit confirmation before the same native approve and advance commands', async () => {
  const wrapper = render();
  await wrapper.setProps({ owners: [[7, 'Native responsible analyst']] });
  await flushPromises();
  expect(
    wrapper.get('[data-test="master-allocation-summary"]').text()
  ).toContain('1 alocações a criar');
  expect(wrapper.text()).toContain('Native responsible analyst');
  expect(wrapper.get('[data-test="review-approve"]').element.disabled).toBe(
    true
  );
  await wrapper
    .get('[data-test="master-allocation-confirmation"]')
    .setValue(true);
  await wrapper.get('[data-test="review-approve"]').trigger('click');
  await flushPromises();
  expect(mocks.api.approvePortfolioBatch).toHaveBeenCalledWith(
    '1400',
    91,
    preview.digest,
    expect.any(Object)
  );
  await wrapper.get('[data-test="review-advance"]').trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain(
    messages.RELATIONSHIP.REVIEWED_BATCH.STATES.completed
  );
  expect(mocks.api.previewPortfolioBatch).toHaveBeenCalledOnce();
});

it('rejects HTTP200 receipts that claim a different native company result instead of showing a successful completion', async () => {
  const changed = structuredClone(completed);
  changed.items[1].receipt.assignment_id = 99;
  mocks.api.advancePortfolioBatch.mockResolvedValueOnce({ data: changed });
  const wrapper = render();
  await flushPromises();
  await wrapper
    .get('[data-test="master-allocation-confirmation"]')
    .setValue(true);
  await wrapper.get('[data-test="review-approve"]').trigger('click');
  await flushPromises();
  await wrapper.get('[data-test="review-advance"]').trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain(
    messages.RELATIONSHIP.NAMED_PORTFOLIOS.BATCH.UNCONFIRMED
  );
  expect(wrapper.find('[data-test="master-allocation-summary"]').exists()).toBe(
    false
  );
});

it('keeps unknown private workload blocked and rejects leaked frozen source IDs', async () => {
  const changed = structuredClone(preview);
  changed.master_capacity = {
    state: 'projected',
    rows: [
      {
        scope_key: 'account',
        configuration_version: 1,
        user_id: 7,
        unit: 'hours',
        blocker: 'capacity_scope_denied',
      },
    ],
  };
  mocks.api.previewPortfolioBatch.mockResolvedValueOnce({ data: changed });
  const wrapper = render();
  await flushPromises();
  await wrapper
    .get('[data-test="master-allocation-confirmation"]')
    .setValue(true);
  expect(wrapper.get('[data-test="review-approve"]').element.disabled).toBe(
    true
  );
  changed.master_capacity.rows[0].source_assignment_ids = [99];
  expect(validMasterAllocationReview(changed, 18, proposal)).toBe(false);
  expect(mocks.api.approvePortfolioBatch).not.toHaveBeenCalled();
});

it('clears the prepared names and ignores a delayed preview when native authority changes', async () => {
  let finish;
  mocks.api.previewPortfolioBatch.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render();
  await wrapper.setProps({ actorId: 99 });
  finish({ data: structuredClone(preview) });
  await flushPromises();
  expect(wrapper.text()).not.toContain('Synthetic company 11');
  expect(mocks.api.approvePortfolioBatch).not.toHaveBeenCalled();
});

it('re-reviews only unresolved company subjects with fresh native group version and their original creation proposals', async () => {
  const wrapper = render(GroupPanel, { group, proposal }, true);
  const attention = {
    ...structuredClone(preview),
    state: 'attention',
    revision: 4,
    items: [
      completed.items[0],
      {
        ...preview.items[1],
        state: 'failed',
        error_code: 'BATCH_REVIEW_STALE',
      },
    ],
  };
  wrapper.findComponent(NativePanel).vm.$emit('reviewed', attention);
  await flushPromises();
  await wrapper.get('textarea').setValue('Fresh review of unresolved company');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.emitted('proposal')[0][0]).toEqual({
    operation: 'master_allocation',
    ids: [12],
    creations: [],
    portfolio_group_id: 18,
    expected_version: 3,
    previous_review_id: 91,
    justification: 'Fresh review of unresolved company',
    request_id: expect.any(String),
  });
});

it('pages a complete reviewed company audience without another preview or silently dropping subjects', async () => {
  const data = structuredClone(preview);
  data.inputs.ids = Array.from({ length: 12 }, (_, index) => 100 + index);
  data.inputs.creations = [];
  data.summary.create_count = 0;
  data.summary.reuse_count = 12;
  data.items = data.inputs.ids.map(id => ({
    ...structuredClone(preview.items[1]),
    company_id: id,
    label: `Company ${id}`,
  }));
  mocks.api.previewPortfolioBatch.mockResolvedValueOnce({ data });
  const wrapper = render(NativePanel, {
    accountId: '1400',
    actorId: 7,
    portfolioGroupId: 18,
    proposal: data.inputs,
  });
  await flushPromises();
  expect(wrapper.findAll('li')).toHaveLength(10);
  await wrapper.get('[data-test="master-review-next"]').trigger('click');
  expect(wrapper.findAll('li')).toHaveLength(2);
  expect(wrapper.text()).toContain('Company 111');
  expect(mocks.api.previewPortfolioBatch).toHaveBeenCalledOnce();
});

it('recognizes the minimal own-operation inventory without requiring or exposing a frozen audience', () => {
  const row = {
    id: 91,
    revision: 1,
    state: 'previewed',
    operation: 'master_allocation',
    can_cancel_pending: true,
    created_at: '2026-11-07T01:00:00Z',
    updated_at: '2026-11-07T01:00:00Z',
    counts: { pending: 2, applied: 0, failed: 0, canceled: 0, total: 2 },
  };
  expect(validOperationMetadata(row)).toBe(true);
  expect(row).not.toHaveProperty('inputs');
});

it('rejects duplicate native allocation results for distinct master companies', () => {
  const changed = structuredClone(completed);
  changed.items[1].assignment_id = changed.items[0].assignment_id;
  changed.items[1].receipt.assignment_id = changed.items[0].assignment_id;
  expect(validMasterAllocationReview(changed, 18, proposal)).toBe(false);
});

it('displays the captured explicit workload as disabled native fields during review', async () => {
  const data = structuredClone(preview);
  data.items[0].allocation.settings.capacity_workload = { hours: 1.5 };
  mocks.api.previewPortfolioBatch.mockResolvedValueOnce({ data });
  const wrapper = render();
  await flushPromises();
  const workload = wrapper.get('[data-testid="workload-hours"]');
  expect(workload.element.value).toBe('1.5');
  expect(workload.element.closest('fieldset').disabled).toBe(true);
  expect(mocks.api.approvePortfolioBatch).not.toHaveBeenCalled();
});

it('does not accept changed create/reuse decisions under the already reviewed immutable identity', async () => {
  const changed = structuredClone(completed);
  changed.items[0].mode = 'reuse';
  changed.items[0].receipt.allocation_state = 'reused';
  changed.summary.create_count = 0;
  changed.summary.reuse_count = 2;
  expect(validMasterAllocationReview(changed, 18, proposal)).toBe(true);
  expect(validMasterTransition(preview, changed)).toBe(false);
  mocks.api.advancePortfolioBatch.mockResolvedValueOnce({ data: changed });
  const wrapper = render();
  await flushPromises();
  await wrapper
    .get('[data-test="master-allocation-confirmation"]')
    .setValue(true);
  await wrapper.get('[data-test="review-approve"]').trigger('click');
  await flushPromises();
  await wrapper.get('[data-test="review-advance"]').trigger('click');
  await flushPromises();
  expect(wrapper.find('[data-test="master-allocation-summary"]').exists()).toBe(
    false
  );
  expect(wrapper.text()).toContain(
    messages.RELATIONSHIP.NAMED_PORTFOLIOS.BATCH.UNCONFIRMED
  );
});

it('preserves applied native receipts and explicit workloads while allowing only pending subjects to progress', () => {
  const running = {
    ...structuredClone(preview),
    state: 'running',
    revision: 3,
    items: [completed.items[0], preview.items[1]],
  };
  expect(validMasterTransition(running, completed)).toBe(true);
  const changed = structuredClone(completed);
  changed.items[0].receipt.assignment_digest = 'c'.repeat(64);
  expect(validMasterTransition(running, changed)).toBe(false);
  changed.items[0] = structuredClone(completed.items[0]);
  changed.items[1].allocation.settings.capacity_workload = { hours: 99 };
  expect(validMasterTransition(running, changed)).toBe(false);
});
