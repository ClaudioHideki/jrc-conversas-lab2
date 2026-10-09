import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import SurveyAdministrationPanel from './SurveyAdministrationPanel.vue';
import SurveyResponseBox from './SurveyResponseBox.vue';
import SurveyReportFilters from './SurveyReportFilters.vue';
import SurveyReportSummary from './SurveyReportSummary.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: {
    surveyDefinitions: vi.fn(),
    surveyRules: vi.fn(),
    surveyOrigins: vi.fn(),
    saveSurveyConfiguration: vi.fn(),
    surveyConfigurationHistory: vi.fn(),
    duplicateSurveyConfiguration: vi.fn(),
    previewSurveyPolicy: vi.fn(),
    surveyDecisions: vi.fn(),
    treatSurvey: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '12' } });
  mocks.store = { getters: reactive({ getCurrentUserID: 7 }) };
  mocks.api.surveyDefinitions.mockResolvedValue({ data: { payload: [] } });
  mocks.api.surveyRules.mockResolvedValue({ data: { payload: [] } });
  mocks.api.surveyOrigins.mockResolvedValue({
    data: {
      payload: [{ type: 'Conversation', id: 77, label: 'Visible closure' }],
    },
  });
  mocks.api.saveSurveyConfiguration.mockResolvedValue({ data: {} });
  mocks.api.previewSurveyPolicy.mockResolvedValue({
    data: { state: 'blocked', reason: 'consent_missing' },
  });
  mocks.api.treatSurvey.mockResolvedValue({ data: {} });
});
describe('Shared surveys administration and response treatment', () => {
  it('offers only declared response filters and emits them without changing activation', async () => {
    const filters = {
      type: '',
      classification: '',
      treatment_status: '',
      source_type: '',
      channel: '',
      unit_id: '',
      score_min: '',
      score_max: '',
    };
    const wrapper = mount(SurveyReportFilters, {
      props: { filters, metadata: { survey_units: [[9, 'Authorized unit']] } },
    });
    await wrapper.find('[data-testid="survey-type-filter"]').setValue('nps');
    await wrapper
      .find('[data-testid="survey-classification-filter"]')
      .setValue('detractor');
    expect(wrapper.emitted('update')).toEqual([
      [{ type: 'nps' }],
      [{ classification: 'detractor' }],
    ]);
    expect(filters.type).toBe('');
    expect(mocks.api.saveSurveyConfiguration).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('does not fetch or expose administration controls without permission', async () => {
    const wrapper = mount(SurveyAdministrationPanel, {
      props: { allowed: false },
    });
    await flushPromises();
    expect(mocks.api.surveyDefinitions).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="new-survey-config"]').exists()).toBe(
      false
    );
    wrapper.unmount();
  });
  it('creates drafts and rules OFF by default and sends a versioned account-bound payload', async () => {
    const wrapper = mount(SurveyAdministrationPanel, {
      props: { allowed: true, metadata: { execution_members: [[7, 'CS']] } },
    });
    await flushPromises();
    await wrapper.get('[data-testid="new-survey-config"]').trigger('click');
    const form = wrapper.get('[data-testid="survey-config-form"]');
    await wrapper.get('[data-testid="survey-name"]').setValue('NPS published');
    await form.findAll('input')[1].setValue('nps_published');
    await form.get('textarea').setValue('Survey question');
    await form.trigger('submit');
    expect(mocks.api.saveSurveyConfiguration).toHaveBeenCalledWith(
      '12',
      'definitions',
      expect.objectContaining({
        status: 'draft',
        settings: expect.objectContaining({ recovery_enabled: false }),
      })
    );
    await flushPromises();
    await wrapper.findAll('nav button')[2].trigger('click');
    await wrapper.get('[data-testid="new-survey-config"]').trigger('click');
    expect(
      wrapper.get('[data-testid="survey-rule-active"]').element.checked
    ).toBe(false);
    wrapper.unmount();
  });
  it('previews only a granted native origin without creating a dispatch or changing activation', async () => {
    const wrapper = mount(SurveyAdministrationPanel, {
      props: { allowed: true },
    });
    await flushPromises();
    await wrapper.findAll('nav button')[4].trigger('click');
    await wrapper.get('select').setValue('0');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.api.previewSurveyPolicy).toHaveBeenCalledWith('12', {
      source_type: 'Conversation',
      source_id: 77,
      cycle_key: 'administrative-preview',
    });
    expect(mocks.api.saveSurveyConfiguration).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('discards stale definitions and origins after an account switch', async () => {
    let resolveOld;
    mocks.api.surveyDefinitions.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = mount(SurveyAdministrationPanel, {
      props: { allowed: true },
    });
    mocks.route.params.accountId = '13';
    await flushPromises();
    resolveOld({
      data: {
        payload: [
          {
            id: 1,
            name: 'Private old account definition',
            status: 'draft',
            version: 1,
          },
        ],
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('Private old account definition');
    expect(mocks.api.surveyDefinitions).toHaveBeenLastCalledWith(
      '13',
      expect.any(Object)
    );
    wrapper.unmount();
  });
  it('keeps the published response visible while treatment updates separate fields', async () => {
    const wrapper = mount(SurveyResponseBox, {
      props: {
        canManage: true,
        survey: {
          id: 33,
          classification: 'detractor',
          responded_at: '2026-10-08',
          source_type: 'Conversation',
          cycle_key: 'cycle',
          definition_version: 1,
          definition_snapshot: {
            name: 'Frozen model',
            questions: [{ key: 'rating', text: 'Frozen question' }],
          },
          answers: { rating: 3 },
        },
      },
    });
    await wrapper.get('select').setValue('treated');
    await wrapper.get('textarea').setValue('Customer contacted');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.api.treatSurvey).toHaveBeenCalledWith('12', 33, {
      treatment_status: 'treated',
      treatment_cause: 'Customer contacted',
    });
    expect(wrapper.text()).toContain('Frozen question');
    expect(wrapper.emitted('changed')).toHaveLength(1);
    wrapper.unmount();
  });
  it('uses authorized native source and recovery links without deriving a route from hidden metadata', () => {
    const riskRoute = {
      name: 'jrc_relationship_risks',
      params: { accountId: 12 },
      query: { assignment_id: 7, record_id: 55 },
    };
    const wrapper = mount(SurveyResponseBox, {
      props: {
        survey: {
          id: 33,
          source_links: [{ kind: 'risk', id: 55, route: riskRoute }],
          metadata: { recovery_action_id: 999 },
        },
      },
      global: {
        stubs: {
          RouterLink: {
            name: 'RouterLink',
            props: ['to'],
            template: '<a><slot /></a>',
          },
        },
      },
    });
    const links = wrapper.findAllComponents({ name: 'RouterLink' });
    expect(links).toHaveLength(1);
    expect(links[0].props('to')).toEqual(riskRoute);
    expect(wrapper.text()).not.toContain('999');
    wrapper.unmount();
  });
  it('shows filtered response metrics and the provided daily trend on each published scale', () => {
    const wrapper = mount(SurveyReportSummary, {
      props: {
        report: {
          response_count: 3,
          nps: -100,
          csat: 4.5,
          ces: null,
          trend: [
            {
              day: '2026-10-08',
              kind: 'nps',
              response_count: 1,
              average_score: 3,
              nps: -100,
            },
          ],
        },
      },
    });
    expect(
      wrapper.get('[data-testid="survey-report-summary"]').text()
    ).toContain('-100');
    expect(wrapper.text()).toContain('4.5');
    expect(wrapper.get('tbody').text()).toContain('2026-10-08');
    expect(wrapper.get('tbody').text()).toContain('3');
    wrapper.unmount();
  });
});
