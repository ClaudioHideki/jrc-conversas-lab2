import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive, ref } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import { fixedSurveyScope } from '../../jrcRelationship/fixedSurveyScope';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  session: null,
  api: {
    metadata: vi.fn(),
    records: vi.fn(),
    dashboard: vi.fn(),
    portfolio: vi.fn(),
    exportSurveys: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));
vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
import ModulePage from '../../jrcRelationship/ModulePage.vue';
import NativeSurveysView from '../views/NativeSurveysView.vue';
import CatalogView from '../views/CatalogView.vue';
let wrapper;
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1' }, query: {} });
  mocks.store = { getters: reactive({ getCurrentUserID: '7' }) };
  mocks.session = {
    accountId: ref('1'),
    userId: ref('7'),
    enabled: ref(true),
    state: reactive({
      status: 'ready',
      context: {
        account_id: '1',
        user_id: '7',
        units: [
          { id: '10', operator_company: { id: '3' } },
          { id: '11', operator_company: { id: '4' } },
        ],
        capabilities: { surveys: { index: true }, contracts: { index: true } },
      },
    }),
    resource: () => ({ status: 'idle', items: [], meta: null }),
    load: vi.fn(),
    resetResource: vi.fn(),
    retry: vi.fn(),
  };
  mocks.api.metadata.mockResolvedValue({
    data: {
      owners: [],
      teams: [],
      business_units: [],
      segments: [],
      products: [],
      pipelines: [],
      can_manage: true,
      survey_units: [[10, 'Native unit']],
    },
  });
  mocks.api.records.mockResolvedValue({
    data: { payload: [], meta: { page: 1, per_page: 25, total: 0 } },
  });
});
afterEach(() => wrapper?.unmount());
const fixed = unit => ({
  source_type: 'JrcServiceDesk::Ticket',
  unit_id: unit,
});
describe('native Service Desk surveys and contract lookup reuse', () => {
  it('does not mount any account-wide survey module until an explicitly authorized unit is chosen', async () => {
    wrapper = shallowMount(NativeSurveysView);
    await flushPromises();
    expect(wrapper.findComponent(ModulePage).exists()).toBe(false);
    wrapper.findComponent({ name: 'ScopeBar' }).vm.$emit('update:unitId', '10');
    await flushPromises();
    expect(wrapper.findComponent(ModulePage).props('fixedSurveyScope')).toEqual(
      fixed('10')
    );
    wrapper
      .findComponent({ name: 'ScopeBar' })
      .vm.$emit('update:unitId', '999');
    await flushPromises();
    expect(wrapper.findComponent(ModulePage).exists()).toBe(false);
    expect(mocks.api.records).not.toHaveBeenCalled();
  });
  it('unmounts the native survey source and clears unit selection on current grant/context revocation', async () => {
    wrapper = shallowMount(NativeSurveysView);
    wrapper.findComponent({ name: 'ScopeBar' }).vm.$emit('update:unitId', '10');
    await flushPromises();
    expect(wrapper.findComponent(ModulePage).exists()).toBe(true);
    mocks.session.state.context.capabilities.surveys.index = false;
    await flushPromises();
    expect(wrapper.findComponent(ModulePage).exists()).toBe(false);
    mocks.session.state.context = {
      ...mocks.session.state.context,
      account_id: '2',
      capabilities: { surveys: { index: true } },
    };
    await flushPromises();
    expect(wrapper.findComponent(ModulePage).exists()).toBe(false);
  });
  it('uses only existing scoped metadata/records, prevents an origin/unit override and reloads on explicit unit change', async () => {
    wrapper = shallowMount(ModulePage, {
      props: { screen: 'surveys', fixedSurveyScope: fixed('10') },
    });
    await flushPromises();
    expect(mocks.api.records).toHaveBeenLastCalledWith(
      '1',
      'surveys',
      expect.objectContaining(fixed('10')),
      expect.objectContaining({ signal: expect.any(AbortSignal) })
    );
    expect(mocks.api.portfolio).not.toHaveBeenCalled();
    expect(mocks.api.dashboard).not.toHaveBeenCalled();
    expect(
      wrapper.findComponent({ name: 'SurveyReportFilters' }).props('fixedScope')
    ).toBe(true);
    wrapper
      .findComponent({ name: 'SurveyReportFilters' })
      .vm.$emit('update', { source_type: 'Call', unit_id: '999' });
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(mocks.api.records).toHaveBeenLastCalledWith(
      '1',
      'surveys',
      expect.objectContaining(fixed('10')),
      expect.anything()
    );
    expect(wrapper.text()).not.toContain('RELATIONSHIP.NEW');
    expect(
      wrapper.findComponent({ name: 'SurveyPreparationPanel' }).exists()
    ).toBe(false);
    await wrapper.setProps({ fixedSurveyScope: fixed('11') });
    await flushPromises();
    expect(mocks.api.records).toHaveBeenLastCalledWith(
      '1',
      'surveys',
      expect.objectContaining(fixed('11')),
      expect.anything()
    );
  });
  it.each([
    { source_type: 'Call', unit_id: '10' },
    { source_type: 'JrcServiceDesk::Ticket' },
    { ...fixed('10'), arbitrary: true },
    fixed('0'),
  ])(
    'rejects a malformed fixed scope before requesting native sources: %j',
    async scope => {
      expect(() => fixedSurveyScope(scope, 'surveys')).toThrow();
      wrapper = shallowMount(ModulePage, {
        props: { screen: 'surveys', fixedSurveyScope: scope },
      });
      await flushPromises();
      expect(mocks.api.metadata).not.toHaveBeenCalled();
      expect(mocks.api.records).not.toHaveBeenCalled();
    }
  );
  it('retains optional legacy behavior and rejects a fixed source in a different module screen', () => {
    expect(fixedSurveyScope(null, 'portfolio')).toBeNull();
    expect(() => fixedSurveyScope(fixed('10'), 'portfolio')).toThrow();
  });
  it('requires an explicit unit before reading the existing contract lookup and shows only canonical identifiers', async () => {
    const result = reactive({ status: 'idle', items: [], meta: null });
    mocks.session.resource = () => result;
    wrapper = shallowMount(CatalogView, {
      props: { resource: 'contracts', screen: 'contracts' },
      global: {
        stubs: {
          Panel: { template: '<section><slot /></section>' },
          BaseTable: {
            name: 'BaseTable',
            props: ['headers', 'items'],
            template: '<table><slot name="row" /></table>',
          },
          BaseTableRow: {
            name: 'BaseTableRow',
            template: '<tr><slot /></tr>',
          },
          BaseTableCell: { template: '<td><slot /></td>' },
        },
      },
    });
    await flushPromises();
    expect(mocks.session.load).not.toHaveBeenCalled();
    expect(wrapper.findComponent({ name: 'ScopeBar' }).props('required')).toBe(
      true
    );
    mocks.route.query = { unit_id: '10' };
    await flushPromises();
    expect(mocks.session.load).toHaveBeenCalledWith(
      'catalog:contracts',
      'contracts',
      { unit_id: '10' }
    );
    expect(wrapper.findComponent({ name: 'BaseTable' }).exists()).toBe(false);
    expect(
      wrapper.findAll('.sd-column-hints span').map(node => node.text())
    ).toEqual([
      'JRC_SERVICE_DESK.FIELDS.name',
      'JRC_SERVICE_DESK.FIELDS.contact_id',
      'JRC_SERVICE_DESK.FIELDS.company_id',
    ]);
    result.status = 'ready';
    result.items = [
      {
        id: '9007199254740993',
        name: 'Contract LAB',
        contact_id: '9007199254740995',
        company_id: '9007199254740997',
      },
    ];
    await flushPromises();
    expect(
      wrapper.findComponent({ name: 'BaseTable' }).props('headers')
    ).toEqual([
      'JRC_SERVICE_DESK.FIELDS.name',
      'JRC_SERVICE_DESK.FIELDS.contact_id',
      'JRC_SERVICE_DESK.FIELDS.company_id',
      'JRC_SERVICE_DESK.COMMON.actions',
    ]);
    wrapper
      .findComponent({ name: 'BaseTableRow' })
      .findComponent({ name: 'Button' })
      .vm.$emit('click');
    await flushPromises();
    expect(wrapper.findAll('dl dt').map(node => node.text())).toEqual([
      'JRC_SERVICE_DESK.FIELDS.name',
      'JRC_SERVICE_DESK.FIELDS.contact_id',
      'JRC_SERVICE_DESK.FIELDS.company_id',
    ]);
    expect(wrapper.findAll('dl dd').map(node => node.text())).toEqual([
      'Contract LAB',
      '9007199254740995',
      '9007199254740997',
    ]);
    expect(
      wrapper
        .findAllComponents({ name: 'Input' })
        .map(node => node.props('label'))
    ).toEqual(['JRC_SERVICE_DESK.COMMON.search']);
    expect(wrapper.findComponent({ name: 'CompanyPicker' }).exists()).toBe(
      false
    );
    expect(
      wrapper.findComponent({ name: 'ConfigurationManager' }).exists()
    ).toBe(false);
    expect(wrapper.text()).toContain('JRC_SERVICE_DESK.COMMON.read_only');
    expect(wrapper.text()).toContain('JRC_SERVICE_DESK.CATALOG.contract_hint');
  });
});
