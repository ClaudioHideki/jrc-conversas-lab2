import { afterEach, describe, expect, it } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, mount } from '@vue/test-utils';
import {
  teamRosterReviewAuthority,
  useTeamRosterWithdrawalReview,
} from './useTeamRosterWithdrawalReview';

enableAutoUnmount(afterEach);
const parameters = () => ({
  accountId: ref('1'),
  teamId: ref(2),
  agentsList: ref([3]),
  authority: ref({ configure: true }),
});
const reply = (changes = {}) => ({
  response: {
    status: 409,
    data: {
      error: 'team_roster_confirmation_required',
      review: {
        account_id: '1',
        team_id: '2',
        team_name: 'SYNTHETIC team',
        operation: 'update',
        queues: [
          {
            queue_id: '4',
            queue_name: 'SYNTHETIC impacted queue',
            unit_id: '5',
            previous_count: 2,
            remaining_count: 0,
          },
        ],
        review_token: 'synthetic-client-only-receipt',
        ...changes,
      },
    },
  },
});
const render = params =>
  mount(
    defineComponent({
      setup: () => useTeamRosterWithdrawalReview(params),
      render: () => h('div'),
    })
  );

describe('manager review for a native team roster withdrawal', () => {
  it('requires explicit confirmation of the actual impact before supplying the receipt', () => {
    const wrapper = render(parameters());
    expect(wrapper.vm.handleError(reply(), wrapper.vm.fingerprint())).toBe(
      true
    );
    expect(wrapper.vm.canSave).toBe(false);
    expect(wrapper.vm.options()).toEqual({});
    wrapper.vm.state.confirmed = true;
    expect(wrapper.vm.canSave).toBe(true);
    expect(wrapper.vm.options()).toEqual({
      managerConfirmation: {
        confirmed: true,
        review_token: 'synthetic-client-only-receipt',
      },
    });
  });

  ['accountId', 'teamId', 'agentsList', 'authority'].forEach(field => {
    it(`invalidates the review synchronously when ${field} changes`, () => {
      const params = parameters();
      const wrapper = render(params);
      wrapper.vm.handleError(reply(), wrapper.vm.fingerprint());
      wrapper.vm.state.confirmed = true;
      const values = {
        accountId: '9',
        teamId: 9,
        agentsList: [3, 8],
        authority: { configure: false },
      };
      params[field].value = values[field];
      expect(wrapper.vm.state.review).toBeNull();
      expect(wrapper.vm.state.confirmed).toBe(false);
      expect(wrapper.vm.options()).toEqual({});
    });
  });

  it('does not expose a late review response after an account or draft switch', () => {
    const params = parameters();
    const wrapper = render(params);
    const key = wrapper.vm.fingerprint();
    params.accountId.value = '9';
    expect(wrapper.vm.handleError(reply(), key)).toBe(true);
    expect(wrapper.vm.state.review).toBeNull();
    expect(wrapper.vm.options()).toEqual({});
  });

  it('does not accept an old response after returning to the original account context', () => {
    const params = parameters();
    const wrapper = render(params);
    const previous = wrapper.vm.fingerprint();
    params.accountId.value = '9';
    params.accountId.value = '1';
    wrapper.vm.handleError(reply(), previous);
    expect(wrapper.vm.state.review).toBeNull();
    expect(wrapper.vm.options()).toEqual({});
  });

  it('invalidates in-flight responses when the manager explicitly cancels the review', () => {
    const wrapper = render(parameters());
    const previous = wrapper.vm.fingerprint();
    wrapper.vm.clear();
    wrapper.vm.handleError(reply(), previous);
    expect(wrapper.vm.state.review).toBeNull();
    expect(wrapper.vm.options()).toEqual({});
  });

  [
    { account_id: '9' },
    { team_id: '9' },
    { operation: 'destroy' },
    { review_token: '' },
    { queues: [] },
    {
      queues: [
        {
          queue_id: 4,
          unit_id: 5,
          queue_name: 'SYNTHETIC malformed',
          previous_count: 0,
          remaining_count: 0,
        },
      ],
    },
  ].forEach(changes => {
    it(`rejects malformed or mismatched review ${JSON.stringify(changes)}`, () => {
      const wrapper = render(parameters());
      wrapper.vm.handleError(reply(changes), wrapper.vm.fingerprint());
      expect(wrapper.vm.state.error).toBe(true);
      expect(wrapper.vm.state.review).toBeNull();
      expect(wrapper.vm.canSave).toBe(false);
    });
  });

  it('does not silently discard duplicated queue identities', () => {
    const error = reply();
    error.response.data.review.queues.push({
      ...error.response.data.review.queues[0],
    });
    const wrapper = render(parameters());
    wrapper.vm.handleError(error, wrapper.vm.fingerprint());
    expect(wrapper.vm.state.error).toBe(true);
    expect(wrapper.vm.options()).toEqual({});
  });

  it('clears private impact on denied access while preserving the selected roster draft', () => {
    const params = parameters();
    const wrapper = render(params);
    const key = wrapper.vm.fingerprint();
    wrapper.vm.handleError(reply(), key);
    expect(wrapper.vm.handleError({ response: { status: 403 } }, key)).toBe(
      false
    );
    expect(wrapper.vm.state.review).toBeNull();
    expect(params.agentsList.value).toEqual([3]);
  });

  it('keeps a same-context selected draft and reviewed receipt during an ordinary transport failure', () => {
    const wrapper = render(parameters());
    const key = wrapper.vm.fingerprint();
    wrapper.vm.handleError(reply(), key);
    wrapper.vm.state.confirmed = true;
    expect(wrapper.vm.handleError(new Error('network unavailable'), key)).toBe(
      false
    );
    expect(wrapper.vm.canSave).toBe(true);
    expect(wrapper.vm.options()).toHaveProperty(
      'managerConfirmation.review_token'
    );
  });

  it('uses only current-account authority fields, excluding presence and unrelated account data', () => {
    const user = {
      id: 7,
      name: 'SYNTHETIC user',
      accounts: [
        {
          id: 1,
          role: 'administrator',
          custom_role_id: 8,
          permissions: ['a'],
          availability: 'online',
        },
        { id: 2, role: 'agent', custom_role_id: 99 },
      ],
    };
    const initial = teamRosterReviewAuthority(user, '1');
    user.accounts[0].availability = 'offline';
    expect(teamRosterReviewAuthority(user, '1')).toEqual(initial);
    expect(initial).not.toHaveProperty('name');
    expect(initial.customRoleId).toBe(8);
    user.accounts[0].custom_role_id = 9;
    expect(teamRosterReviewAuthority(user, '1')).not.toEqual(initial);
  });
});
