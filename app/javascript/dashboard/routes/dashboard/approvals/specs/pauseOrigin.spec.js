import { afterEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { validPauseOrigin } from '../pauseOriginPresentation';
import PauseOrigin from '../PauseOrigin.vue';
import RequestDetail from '../RequestDetail.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
    te: () => true,
    locale: { value: 'pt_BR' },
  }),
}));
vi.mock('dashboard/components-next/dialog/Dialog.vue', () => ({
  default: {
    name: 'Dialog',
    emits: ['confirm', 'close'],
    setup(_, { expose }) {
      expose({ open: vi.fn() });
    },
    template: '<section role="dialog"><slot /><slot name="footer" /></section>',
  },
}));
vi.mock('../AuthorityOrigin.vue', () => ({
  default: { template: '<span />' },
}));
vi.mock('../DistributionApprovalOrigin.vue', () => ({
  default: { template: '<span />' },
}));
vi.mock('../ApprovalOriginLink.vue', () => ({
  default: { template: '<span />' },
}));
vi.mock('../AdjustmentDialog.vue', () => ({
  default: { template: '<span />' },
}));
vi.mock('../FinancialAdjustmentDialog.vue', () => ({
  default: { template: '<span />' },
}));
vi.mock('../ReviewDirectionsPanel.vue', () => ({
  default: { template: '<span />' },
}));
vi.mock('../ApprovalRequestReport.vue', () => ({
  default: { template: '<span />' },
}));
enableAutoUnmount(afterEach);
const request = () => ({
  id: 7,
  resource_id: 2,
  resource_type: 'JrcContactCenter::PauseApprovalScope',
  module_key: 'contact_center',
  event_key: 'pause',
  state: 'pending',
  lock_version: 0,
  cycle: 1,
  requester_name: 'SYNTHETIC requester',
  policy_name: 'SYNTHETIC scoped policy',
  created_at: '2026-11-22T10:00:00Z',
  expires_at: '2026-11-22T11:00:00Z',
  issuer_company_id: 10,
  business_unit_id: 11,
  stages: [{ code: 'review', quorum: 1, approved_count: 0 }],
  allowed_decisions: [
    { step_code: 'review', choices: [{ actions: ['approved'] }] },
  ],
  origin: {
    kind: 'contact_center_pause',
    scope_id: '2',
    historical: true,
    own_scope_only: true,
    local_only: true,
    provider_confirmed: false,
    context_digest: 'a'.repeat(64),
    justification_digest: 'b'.repeat(64),
    reason_code: 'synthetic_break',
    reason_label: 'SYNTHETIC pausa revisada',
    scope_unit_ids: ['20'],
    scope_unit_names: ['SYNTHETIC unidade própria'],
    unit_count: 1,
  },
});

describe('native Central pause source presentation', () => {
  it('explains the pause context without applying commercial-only guidance to the new source', () => {
    const wrapper = mount(RequestDetail, { props: { request: request() } });
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.PAUSE_APPROVAL.SOURCE_HELP'
    );
    expect(wrapper.text()).not.toContain('JRC_APPROVALS.workspace.sourceHelp');
  });

  it('preserves the existing source guidance for an ordinary commercial request', () => {
    const record = request();
    Object.assign(record, {
      module_key: 'crm',
      event_key: 'price_exception',
      resource_type: 'JrcCrm::SalesOrder',
      origin: null,
    });
    const wrapper = mount(RequestDetail, { props: { request: record } });
    expect(wrapper.text()).toContain('JRC_APPROVALS.workspace.sourceHelp');
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.PAUSE_APPROVAL.SOURCE_HELP'
    );
  });

  it('shows only the already-authorized own-scope historical snapshot and its opaque full-impact digest', () => {
    const record = request();
    const wrapper = mount(PauseOrigin, { props: { request: record } });
    expect(validPauseOrigin(record)).toBe(true);
    expect(wrapper.text()).toContain('SYNTHETIC unidade própria');
    expect(wrapper.text()).toContain('SYNTHETIC pausa revisada');
    expect(wrapper.text()).toContain('a'.repeat(64));
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.PAUSE_APPROVAL.ORIGIN_PRIVATE'
    );
    expect(wrapper.text()).not.toContain('SYNTHETIC outra empresa');
  });

  it.each([
    [
      'wrong source kind',
      record => {
        record.origin.kind = 'other';
      },
    ],
    [
      'wrong domain',
      record => {
        record.module_key = 'other';
      },
    ],
    [
      'wrong source identity',
      record => {
        record.origin.scope_id = '99';
      },
    ],
    [
      'live scope claim',
      record => {
        record.origin.historical = false;
      },
    ],
    [
      'whole-account details claim',
      record => {
        record.origin.own_scope_only = false;
      },
    ],
    [
      'provider applied claim',
      record => {
        record.origin.provider_confirmed = true;
      },
    ],
    [
      'missing exact digest',
      record => {
        record.origin.context_digest = 'invalid';
      },
    ],
    [
      'missing reason',
      record => {
        record.origin.reason_label = '';
      },
    ],
    [
      'unbalanced labels',
      record => {
        record.origin.scope_unit_names = [];
      },
    ],
    [
      'duplicated unit',
      record => {
        record.origin.scope_unit_ids.push('20');
        record.origin.scope_unit_names.push('duplicate');
        record.origin.unit_count = 2;
      },
    ],
  ])('rejects %s without pretending the source was reviewed', (_, change) => {
    const record = request();
    change(record);
    const wrapper = mount(PauseOrigin, { props: { request: record } });
    expect(validPauseOrigin(record)).toBe(false);
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.PAUSE_APPROVAL.ORIGIN_UNVERIFIED'
    );
    expect(wrapper.text()).not.toContain('SYNTHETIC unidade própria');
  });

  it('keeps a native approval choice disabled when its new pause source is incoherent', async () => {
    const record = request();
    record.origin.scope_unit_names = [];
    const wrapper = mount(RequestDetail, {
      props: {
        request: record,
        context: {
          account_id: '1',
          member_id: '9',
          scopes: [
            {
              issuer_company_id: 10,
              business_unit_id: 11,
              company_name: 'SYNTHETIC issuer',
              unit_name: 'SYNTHETIC native business',
            },
          ],
        },
      },
    });
    await wrapper
      .get('textarea')
      .setValue('SYNTHETIC explicit reviewer reason');
    const approve = wrapper
      .findAll('button')
      .find(button => button.text().includes('decisionLabels.approved'));
    expect(approve.attributes('disabled')).toBeDefined();
    await approve.trigger('click');
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.emitted('decide')).toBeUndefined();
  });

  it('closes a pending native confirmation if its required origin changes without emitting any decision', async () => {
    const record = request();
    const wrapper = mount(RequestDetail, {
      props: {
        request: record,
        context: {
          account_id: '1',
          member_id: '9',
          scopes: [
            {
              issuer_company_id: 10,
              business_unit_id: 11,
              company_name: 'SYNTHETIC issuer',
              unit_name: 'SYNTHETIC native business',
            },
          ],
        },
      },
    });
    await wrapper
      .get('textarea')
      .setValue('SYNTHETIC explicit reviewer reason');
    const approve = wrapper
      .findAll('button')
      .find(button => button.text().includes('decisionLabels.approved'));
    await approve.trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
    expect(wrapper.find('[role="dialog"]').text()).toContain(
      'SYNTHETIC unidade própria'
    );
    await wrapper.setProps({
      request: {
        ...record,
        origin: { ...record.origin, scope_unit_names: [] },
      },
    });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.emitted('decide')).toBeUndefined();
  });
});
