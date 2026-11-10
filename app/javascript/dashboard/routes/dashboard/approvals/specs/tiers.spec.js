import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import { beforeEach, expect, it, vi } from 'vitest';
import locale from 'dashboard/i18n/locale/en/jrcApprovals.json';
import TierBound from '../TierBound.vue';
import TierEditor from '../TierEditor.vue';
import TierSummary from '../TierSummary.vue';
import PolicyEditor from '../PolicyEditor.vue';
import { copy, emptyDefinition, emptyStep } from '../model';
const api = vi.hoisted(() => ({ get: vi.fn() }));
vi.mock('dashboard/api/approvals', () => ({ approvalClient: () => api }));
const fields = {
  total_cents: 'integer',
  discount_percentage: 'decimal',
  price_status: 'string',
};
const identities = {
  account_users: [
    { id: 20, name: 'Native manager' },
    { id: 30, name: 'Native director' },
  ],
};
const stages = () => [
  {
    ...emptyStep(),
    code: 'private_manager',
    mode: 'any',
    quorum: 1,
    authority: { const: true },
    on_reject: 'rejected',
    assignees: [{ type: 'account_user', id: 20 }],
  },
  {
    ...emptyStep(),
    code: 'private_director',
    mode: 'any',
    quorum: 1,
    authority: { const: true },
    on_reject: 'rejected',
    assignees: [{ type: 'account_user', id: 30 }],
  },
];
const tiers = () => ({
  field: 'total_cents',
  currency: null,
  min: 0,
  max: null,
  coverage: 'complete',
  rows: [
    {
      min: 0,
      max: 2000,
      min_inclusive: true,
      max_inclusive: true,
      step_codes: ['private_manager'],
    },
    {
      min: 2000,
      max: null,
      min_inclusive: false,
      max_inclusive: false,
      step_codes: ['private_director'],
    },
  ],
});
const context = {
  account_id: 17,
  scopes: [
    {
      issuer_company_id: 4,
      business_unit_id: 6,
      capabilities: ['policy_manage'],
    },
  ],
};
const policy = version => ({
  id: 7,
  name: 'Native rule',
  code: 'hidden_rule',
  module_key: 'crm',
  event_key: 'proposal_send',
  issuer_company_id: 4,
  business_unit_id: 6,
  state: 'draft',
  draft_definition: {
    ...emptyDefinition(),
    schema_version: version,
    steps: stages(),
    selection: { mode: 'exclusive', priority: 10 },
    execution: 'sequential',
    expires_in_seconds: 3600,
    ...(version === 2 ? { tiers: tiers() } : {}),
  },
});
const options = props => ({
  props,
  global: {
    plugins: [
      createI18n({ legacy: false, locale: 'en', messages: { en: locale } }),
    ],
    stubs: {
      Button: {
        props: ['label', 'disabled'],
        template: '<button :disabled="disabled">{{ label }}</button>',
      },
    },
  },
});
const harness = () => ({
  components: { TierEditor },
  setup: () => ({ value: ref(tiers()), fields, steps: stages(), identities }),
  template:
    '<TierEditor v-model="value" :fields="fields" :steps="steps" :options="identities" />',
});
const click = async (wrapper, text) => {
  await wrapper
    .findAll('button')
    .find(button => button.text() === text)
    .trigger('click');
  await flushPromises();
};
beforeEach(() => {
  api.get.mockReset();
  api.get.mockImplementation(path =>
    Promise.resolve({
      data:
        path === 'catalogs'
          ? [{ key: 'crm.proposal_send', fields }]
          : identities,
    })
  );
});
it('updates an unbounded endpoint and its inclusion flag as one event, without a stale second write', async () => {
  const wrapper = mount(
    TierBound,
    options({
      modelValue: 20,
      included: true,
      type: 'integer',
      label: 'Boundary',
    })
  );
  await wrapper.find('input[type="checkbox"]').setValue(true);
  expect(wrapper.emitted('change')).toEqual([
    [{ value: null, included: false }],
  ]);
  wrapper.unmount();
});
it('offers only native numeric fields, shows the configured people and hides internal stage identifiers', () => {
  const wrapper = mount(harness(), options());
  const values = wrapper
    .find('select')
    .findAll('option')
    .map(row => row.attributes('value'));
  expect(values).toEqual(['', 'total_cents', 'discount_percentage']);
  expect(wrapper.text()).toContain('Native manager');
  expect(wrapper.text()).toContain('Native director');
  expect(wrapper.text()).not.toMatch(/private_manager|private_director/);
  wrapper.unmount();
});
it('persists atomic lower-bound changes and explicit inclusion without overwriting the new bound', async () => {
  const wrapper = mount(harness(), options());
  const bound = wrapper
    .findAllComponents(TierBound)
    .find(row => row.props('label') === 'From');
  await bound.find('input[type="checkbox"]').setValue(true);
  expect(wrapper.vm.value.rows[0]).toMatchObject({
    min: null,
    min_inclusive: false,
    max: 2000,
    max_inclusive: true,
  });
  await bound.find('input[type="checkbox"]').setValue(false);
  await bound.find('input:not([type="checkbox"])').setValue('10,00');
  await bound.find('input:not([type="checkbox"])').trigger('change');
  expect(wrapper.vm.value.rows[0]).toMatchObject({
    min: 1000,
    min_inclusive: true,
    max: 2000,
  });
  wrapper.unmount();
});
it('changes range approvers using native step references in policy order', async () => {
  const wrapper = mount(harness(), options());
  const labels = wrapper.find('article').findAll('label');
  await labels
    .find(row => row.text().startsWith('Step 2 ·'))
    .find('input')
    .setValue(true);
  expect(wrapper.vm.value.rows[0].step_codes).toEqual([
    'private_manager',
    'private_director',
  ]);
  await labels
    .find(row => row.text().startsWith('Step 1 ·'))
    .find('input')
    .setValue(false);
  expect(wrapper.vm.value.rows[0].step_codes).toEqual(['private_director']);
  wrapper.unmount();
});
it('adds and removes a range without losing the existing range bounds or mapping', async () => {
  const wrapper = mount(harness(), options());
  const original = copy(wrapper.vm.value.rows);
  await click(wrapper, 'Add authority range');
  expect(wrapper.vm.value.rows).toHaveLength(3);
  expect(wrapper.vm.value.rows.slice(0, 2)).toEqual(original);
  await wrapper.findAll('article')[2].find('button').trigger('click');
  expect(wrapper.vm.value.rows).toEqual(original);
  wrapper.unmount();
});
it('does not coerce old integer bounds into a different typed field and keeps explicit stage mapping', async () => {
  const wrapper = mount(harness(), options());
  await wrapper.find('select').setValue('discount_percentage');
  expect(wrapper.vm.value.field).toBe('discount_percentage');
  expect(wrapper.vm.value.rows[0]).toMatchObject({
    min: null,
    max: null,
    min_inclusive: false,
    max_inclusive: false,
    step_codes: ['private_manager'],
  });
  wrapper.unmount();
});
it('renders monetary configuration summaries without floating-point loss or fabricated simulator decisions', () => {
  const data = tiers();
  data.rows[0].max = { amount_cents: 9007199254740991, currency: 'BRL' };
  const wrapper = mount(
    TierSummary,
    options({ tiers: data, steps: stages(), options: identities })
  );
  expect(wrapper.text()).toContain('90071992547409.91 BRL');
  expect(wrapper.text()).toContain('Configuration summary only');
  expect(wrapper.text()).not.toContain('approved');
  wrapper.unmount();
});
it('preserves v1 by default and roundtrips a v2 draft through all-step mode without discarding its ranges', async () => {
  const source = policy(2);
  const before = JSON.stringify(source);
  const wrapper = mount(PolicyEditor, options({ policy: source, context }));
  await flushPromises();
  await wrapper.findAll('[role="tab"]')[2].trigger('click');
  const toggle = wrapper.find('input[type="checkbox"]');
  expect(toggle.element.checked).toBe(true);
  await toggle.setValue(false);
  await click(wrapper, 'Save draft');
  expect(wrapper.emitted('save').at(-1)[0].definition.schema_version).toBe(1);
  expect(wrapper.emitted('save').at(-1)[0].definition).not.toHaveProperty(
    'tiers'
  );
  await toggle.setValue(true);
  await click(wrapper, 'Save draft');
  expect(wrapper.emitted('save').at(-1)[0].definition).toEqual(
    source.draft_definition
  );
  expect(JSON.stringify(source)).toBe(before);
  wrapper.unmount();
  const original = mount(PolicyEditor, options({ policy: policy(1), context }));
  await flushPromises();
  await click(original, 'Save draft');
  expect(original.emitted('save')[0][0].definition.schema_version).toBe(1);
  expect(original.emitted('save')[0][0].definition).not.toHaveProperty('tiers');
  original.unmount();
});
it('removes deleted stage references from the range draft instead of retaining invisible authority assignments', async () => {
  const wrapper = mount(PolicyEditor, options({ policy: policy(2), context }));
  await flushPromises();
  await wrapper.findAll('[role="tab"]')[2].trigger('click');
  const remove = wrapper
    .findAll('button')
    .filter(row => row.text() === 'Remove')
    .at(-1);
  await remove.trigger('click');
  await click(wrapper, 'Save draft');
  const definition = wrapper.emitted('save').at(-1)[0].definition;
  expect(definition.steps).toHaveLength(1);
  expect(definition.tiers.rows[1].step_codes).toEqual([]);
  expect(wrapper.text()).not.toContain('Step 0');
  wrapper.unmount();
});

it('stores monetary input as exact native cents and rejects extra decimals instead of rounding silently', async () => {
  const wrapper = mount(
    TierBound,
    options({
      modelValue: 2000,
      included: true,
      type: 'minor_money',
      label: 'Native amount',
    })
  );
  const input = wrapper.find('input[inputmode="decimal"]');
  expect(input.element.value).toBe('20.00');
  await input.setValue('12,34');
  expect(wrapper.emitted('change').at(-1)[0]).toEqual({
    value: 1234,
    included: true,
  });
  await input.setValue('1.001');
  expect(wrapper.emitted('change').at(-1)[0].value).toBe('1.001');
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(input.attributes('aria-invalid')).toBe('true');
  wrapper.unmount();
});
