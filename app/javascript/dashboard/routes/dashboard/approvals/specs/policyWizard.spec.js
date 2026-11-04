import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { beforeEach, expect, it, vi } from 'vitest';
import locale from 'dashboard/i18n/locale/en/jrcApprovals.json';
import PolicyEditor from '../PolicyEditor.vue';
import StepEditor from '../StepEditor.vue';
import ConditionEditor from '../ConditionEditor.vue';
import { emptyDefinition, emptyStep } from '../model';
import { conditionSummary } from '../conditionSummary';
const api = vi.hoisted(() => ({ get: vi.fn() }));
vi.mock('dashboard/api/approvals', () => ({ approvalClient: () => api }));
const context = {
  account_id: 17,
  scopes: [
    {
      issuer_company_id: 4,
      business_unit_id: 6,
      company_name: 'Synthetic issuer',
      unit_name: 'Synthetic unit',
      capabilities: ['policy_manage'],
    },
  ],
};
const fields = { discount_percentage: 'decimal', total_cents: 'integer' };
const catalog = [{ key: 'crm.proposal_send', fields }];
const definition = () => ({
  ...emptyDefinition(),
  condition: { field: 'discount_percentage', op: 'gt', value: '10' },
  selection: { mode: 'accumulate', priority: 2 },
  execution: 'parallel',
  expires_in_seconds: 4000,
  delegation_allowed: true,
  reopen_mode: 'restart_all',
  steps: [
    {
      ...emptyStep(),
      code: 'DO_NOT_RENAME'.toLowerCase(),
      mode: 'quorum',
      quorum: 2,
      assignees: [{ type: 'team', id: 7 }],
      authority: { const: true },
      actions: ['approved', 'returned'],
      on_reject: 'returned',
    },
  ],
});
const policy = () => ({
  id: 3,
  name: 'Existing rule',
  code: 'PRIVATE_INTERNAL_RULE_CODE',
  module_key: 'crm',
  event_key: 'proposal_send',
  issuer_company_id: 4,
  business_unit_id: 6,
  state: 'draft',
  draft_definition: definition(),
});
const i18n = () =>
  createI18n({ legacy: false, locale: 'en', messages: { en: locale } });
const options = props => ({
  props,
  global: {
    plugins: [i18n()],
    stubs: {
      Button: {
        props: ['label', 'disabled'],
        template: '<button :disabled="disabled">{{ label }}</button>',
      },
    },
  },
});
const click = async (wrapper, text) => {
  await wrapper
    .findAll('button')
    .find(row => row.text() === text)
    .trigger('click');
  await flushPromises();
};
beforeEach(() =>
  api.get.mockReset().mockImplementation(path =>
    Promise.resolve({
      data:
        path === 'catalogs'
          ? catalog
          : { teams: [{ id: 7, name: 'Native team' }] },
    })
  )
);
it('has exactly four keyboard-accessible steps plus back and next navigation', async () => {
  const wrapper = mount(PolicyEditor, options({ context }));
  expect(wrapper.findAll('[role="tab"]').map(row => row.text())).toEqual([
    '1. What requires approval',
    '2. When approval is required',
    '3. Who approves',
    '4. Review and activate',
  ]);
  await click(wrapper, 'Next');
  expect(wrapper.findAll('[role="tab"]')[1].attributes('aria-selected')).toBe(
    'true'
  );
  await click(wrapper, 'Previous');
  await wrapper.findAll('[role="tab"]')[0].trigger('keydown', { key: 'End' });
  await flushPromises();
  expect(wrapper.findAll('[role="tab"]')[3].attributes('aria-selected')).toBe(
    'true'
  );
  expect(wrapper.findAll('button').some(row => row.text() === 'Next')).toBe(
    false
  );
  wrapper.unmount();
});
it('saves a native draft with an explicit scope and unique hidden step identifiers, omitting only the new rule code', async () => {
  const wrapper = mount(PolicyEditor, options({ context }));
  await wrapper.find('input').setValue('Synthetic new rule');
  await wrapper.findAll('select')[0].setValue('0');
  await flushPromises();
  await wrapper.findAll('select')[1].setValue('crm.proposal_send');
  await wrapper.findAll('[role="tab"]')[2].trigger('click');
  await click(wrapper, 'Add step');
  await click(wrapper, 'Add step');
  expect(wrapper.findAllComponents(StepEditor)).toHaveLength(2);
  await click(wrapper, 'Save draft');
  const body = wrapper.emitted('save')[0][0];
  expect(body).toMatchObject({
    name: 'Synthetic new rule',
    issuer_company_id: 4,
    business_unit_id: 6,
    module_key: 'crm',
    event_key: 'proposal_send',
  });
  expect(body).not.toHaveProperty('code');
  const codes = body.definition.steps.map(row => row.code);
  expect(new Set(codes).size).toBe(2);
  codes.forEach(code => {
    expect(code).toMatch(/^step_[a-f0-9]{32}$/);
    expect(wrapper.text()).not.toContain(code);
  });
  wrapper.unmount();
});
it('preserves all advanced controls, historical step codes, native definition and immutable policy identity while editing', async () => {
  const original = policy();
  const before = JSON.stringify(original);
  const wrapper = mount(PolicyEditor, options({ context, policy: original }));
  await flushPromises();
  expect(wrapper.text()).not.toContain('PRIVATE_INTERNAL_RULE_CODE');
  await wrapper.find('input').setValue('Renamed rule');
  expect(
    wrapper.findAll('button').find(button => button.text() === 'Duplicate rule')
      .element.disabled
  ).toBe(true);
  await wrapper.findAll('[role="tab"]')[2].trigger('click');
  expect(wrapper.findAll('details')).toHaveLength(2);
  expect(
    wrapper.findAll('select').some(row => row.element.value === 'parallel')
  ).toBe(true);
  expect(
    wrapper.findAll('select').some(row => row.element.value === 'restart_all')
  ).toBe(true);
  expect(wrapper.findAllComponents(StepEditor)[0].props('modelValue')).toEqual(
    original.draft_definition.steps[0]
  );
  await click(wrapper, 'Save draft');
  expect(wrapper.emitted('save')[0][0]).toEqual({
    name: 'Renamed rule',
    definition: original.draft_definition,
  });
  expect(JSON.stringify(original)).toBe(before);
  wrapper.unmount();
});
it('shows readable catalog fields and operators without changing their native typed submitted values', async () => {
  const original = { field: 'discount_percentage', op: 'gt', value: '10' };
  const wrapper = mount(
    ConditionEditor,
    options({ modelValue: original, fields })
  );
  const operator = wrapper.findAll('select')[2];
  expect(operator.find('option[value="gt"]').text()).toBe('is greater than');
  expect(wrapper.text()).toContain('Discount (%)');
  await operator.setValue('lte');
  expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual({
    field: 'discount_percentage',
    op: 'lte',
    value: '',
  });
  expect(original.value).toBe('10');
  wrapper.unmount();
});
it('does not offer administrative scopes or save access to a decision-only user', async () => {
  const wrapper = mount(
    PolicyEditor,
    options({
      context: {
        ...context,
        scopes: [{ ...context.scopes[0], capabilities: ['decide'] }],
      },
    })
  );
  await flushPromises();
  expect(wrapper.find('select').findAll('option')).toHaveLength(1);
  expect(
    wrapper.findAll('button').find(row => row.text() === 'Save draft').element
      .disabled
  ).toBe(true);
  expect(api.get).not.toHaveBeenCalled();
  wrapper.unmount();
});
it('summarizes typed conditions in readable language without mutating the structured rule', () => {
  const node = {
    all: [
      { field: 'discount_percentage', op: 'gt', value: '10' },
      { const: true },
    ],
  };
  const before = JSON.stringify(node);
  const text = conditionSummary(node, i18n().global.t);
  expect(text).toBe(
    'All of (Discount (%) is greater than 10; Always requires approval)'
  );
  expect(JSON.stringify(node)).toBe(before);
});

it('duplicates a rule as a detached new draft without its record identity, version or publication state', async () => {
  const source = {
    ...policy(),
    state: 'published',
    enabled: true,
    current_version_id: 81,
    current_version: 3,
  };
  const before = JSON.stringify(source);
  const wrapper = mount(
    PolicyEditor,
    options({ context, templatePolicy: source })
  );
  await flushPromises();
  expect(wrapper.find('input').element.value).toBe('Copy of Existing rule');
  await click(wrapper, 'Save draft');
  const body = wrapper.emitted('save')[0][0];
  expect(body).toEqual({
    name: 'Copy of Existing rule',
    module_key: 'crm',
    event_key: 'proposal_send',
    issuer_company_id: 4,
    business_unit_id: 6,
    definition: source.draft_definition,
  });
  expect(body).not.toHaveProperty('id');
  expect(body).not.toHaveProperty('code');
  expect(body).not.toHaveProperty('state');
  expect(body).not.toHaveProperty('current_version_id');
  expect(
    wrapper
      .findAll('button')
      .some(button => button.text() === 'Publish version')
  ).toBe(false);
  expect(JSON.stringify(source)).toBe(before);
  wrapper.unmount();
});
