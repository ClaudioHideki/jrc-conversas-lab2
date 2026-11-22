import { describe, expect, it } from 'vitest';
import { mount } from '@vue/test-utils';
import PauseApprovalStatus from './PauseApprovalStatus.vue';
import { vi } from 'vitest';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const approval = () => ({
  required: true,
  status: 'ready',
  digest: 'b'.repeat(64),
  local_only: true,
  provider_confirmed: false,
  scopes: [
    {
      id: '1',
      issuer_company_id: '10',
      business_unit_id: '11',
      unit_ids: ['20'],
      status: 'ready',
      requests: [{ id: '7', state: 'approved' }],
    },
  ],
});
const render = value =>
  mount(PauseApprovalStatus, {
    props: { accountId: '1', approval: value },
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

describe('all-scope pause status', () => {
  it('offers an explicit apply action only for a coherent ready receipt', async () => {
    const wrapper = render(approval());
    await wrapper.get('[data-pause-approval-apply]').trigger('click');
    expect(wrapper.emitted('apply')).toHaveLength(1);
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.PAUSE_APPROVAL.READY');
    expect(wrapper.findComponent({ name: 'RouterLink' }).exists()).toBe(true);
    expect(wrapper.findComponent({ name: 'RouterLink' }).props('to')).toEqual({
      name: 'jrc_approvals',
      params: { accountId: '1', screen: 'inbox', id: '7' },
      query: { box: 'requested' },
    });
  });
  it.each([
    [
      'pending scope',
      value => {
        value.scopes[0].status = 'approval_required';
      },
    ],
    [
      'missing scopes',
      value => {
        value.scopes = [];
      },
    ],
    [
      'provider claim',
      value => {
        value.provider_confirmed = true;
      },
    ],
    [
      'bad digest',
      value => {
        value.digest = 'invalid';
      },
    ],
  ])('rejects contradictory readiness: %s', (_, change) => {
    const value = approval();
    change(value);
    const wrapper = render(value);
    expect(wrapper.find('[data-pause-approval-apply]').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.PAUSE_APPROVAL.REVIEW_REQUIRED'
    );
    expect(wrapper.emitted('apply')).toBeUndefined();
  });
});
