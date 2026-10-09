import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import HelpdeskGroupPreview from './HelpdeskGroupPreview.vue';
import { helpdeskDraftChoices, helpdeskDraftInput } from './helpdeskDraftInput';

const mocks = vi.hoisted(() => ({
  api: { groupPreview: vi.fn(), groupPrepare: vi.fn() },
}));
vi.mock('dashboard/api/jrcNicoHelpdesk', () => ({ default: mocks.api }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const choices = {
  campaign: {
    incidents: [{ id: 51, title: 'Exact incident' }],
    inboxes: [{ id: 62, name: 'Authorized inbox' }],
  },
  knowledge: {
    closed_cases: [
      { id: 73, ticket_id: 42, title: 'Authorized historical case' },
    ],
  },
};
const response = (group, rule, actions = []) => ({
  contract_version: 1,
  event_id: 8,
  group_key: group,
  enabled: true,
  executable: actions.length > 0,
  preview: true,
  persisted: false,
  automatic_execution: false,
  preview_digest: 'a'.repeat(64),
  source: { ticket_id: 21, unit_id: 3, rule_key: rule },
  evidence: [],
  missing: [],
  required_fields: [],
  attempts: { recorded: 0, limit: 2, handoff_required: false },
  actions,
  draft_choices: choices,
});
const page = async (rule = 'R04') => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/', component: { template: '<div />' } }],
  });
  await router.push('/');
  await router.isReady();
  return mount(HelpdeskGroupPreview, {
    props: {
      accountId: 12,
      contextKey: '12:7:administrator',
      event: { id: 8, ticket_id: 21, rule_key: rule },
      catalog: ['E', 'C1', 'D2'].map(key => ({ key, name: key })),
    },
    global: {
      plugins: [router],
      stubs: { HelpdeskGroupFields: true },
      mocks: { $t: key => key },
    },
  });
};
const loadChoices = async (wrapper, group, rule) => {
  await wrapper.find('[data-testid="helpdesk-group-select"]').setValue(group);
  mocks.api.groupPreview.mockResolvedValueOnce({ data: response(group, rule) });
  await wrapper
    .find('[data-testid="helpdesk-group-run-preview"]')
    .trigger('click');
  await flushPromises();
};
beforeEach(() => vi.clearAllMocks());

describe('Human-reviewed HelpDesk native drafts', () => {
  it('loads choices only on explicit preview and never selects the first Incident or Inbox', async () => {
    const wrapper = await page();
    await wrapper.find('[data-testid="helpdesk-group-select"]').setValue('C1');
    expect(mocks.api.groupPreview).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="helpdesk-draft-incident"]').exists()
    ).toBe(false);
    await loadChoices(wrapper, 'C1', 'R04');
    expect(
      wrapper.find('[data-testid="helpdesk-draft-incident"]').element.value
    ).toBe('');
    expect(
      wrapper.find('[data-testid="helpdesk-draft-inbox"]').element.value
    ).toBe('');
    expect(
      wrapper.find('[data-testid="helpdesk-draft-name"]').element.value
    ).toBe('');
    expect(mocks.api.groupPreview).toHaveBeenCalledExactlyOnceWith(12, {
      event_id: 8,
      group_key: 'C1',
      input: {},
    });
    expect(mocks.api.groupPrepare).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('prepares the exact reviewed draft through the existing digest approval without launch or message inputs', async () => {
    const wrapper = await page();
    await loadChoices(wrapper, 'C1', 'R04');
    await wrapper
      .find('[data-testid="helpdesk-draft-incident"]')
      .setValue('51');
    await wrapper.find('[data-testid="helpdesk-draft-inbox"]').setValue('62');
    await wrapper
      .find('[data-testid="helpdesk-draft-name"]')
      .setValue(' Reviewed draft ');
    const input = {
      campaign: { incident_id: 51, inbox_id: 62, name: 'Reviewed draft' },
    };
    const action = {
      tool: 'prepare_incident_campaign',
      arguments: {
        event_id: 8,
        source_digest: 'b'.repeat(64),
        ...input.campaign,
      },
      can_prepare: true,
    };
    mocks.api.groupPreview.mockResolvedValueOnce({
      data: response('C1', 'R04', [action]),
    });
    await wrapper
      .find('[data-testid="helpdesk-group-run-preview"]')
      .trigger('click');
    await flushPromises();
    expect(mocks.api.groupPreview).toHaveBeenLastCalledWith(12, {
      event_id: 8,
      group_key: 'C1',
      input,
    });
    expect(mocks.api.groupPrepare).not.toHaveBeenCalled();
    mocks.api.groupPrepare.mockResolvedValueOnce({ data: { id: 91 } });
    await wrapper
      .find('[data-testid="helpdesk-group-prepare"]')
      .trigger('click');
    await flushPromises();
    expect(mocks.api.groupPrepare).toHaveBeenCalledExactlyOnceWith(12, {
      event_id: 8,
      group_key: 'C1',
      input,
      tool: action.tool,
      arguments: action.arguments,
      preview_digest: 'a'.repeat(64),
    });
    wrapper.unmount();
  });

  it('requires a human-written generalized body and explicit review, never copying the historical solution or defaulting consent', async () => {
    const wrapper = await page('R03');
    await loadChoices(wrapper, 'E', 'R03');
    expect(
      wrapper.find('[data-testid="helpdesk-draft-closed-case"]').element.value
    ).toBe('');
    expect(
      wrapper.find('[data-testid="helpdesk-draft-body"]').element.value
    ).toBe('');
    expect(
      wrapper.find('[data-testid="helpdesk-draft-reviewed"]').element.checked
    ).toBe(false);
    await wrapper
      .find('[data-testid="helpdesk-draft-closed-case"]')
      .setValue('73');
    await wrapper
      .find('[data-testid="helpdesk-draft-title"]')
      .setValue('Reviewed generalized lesson');
    await wrapper
      .find('[data-testid="helpdesk-draft-body"]')
      .setValue(' Human generalized text ');
    await wrapper
      .find('[data-testid="helpdesk-draft-reviewed"]')
      .setValue(true);
    const input = {
      knowledge: {
        closed_transition_id: 73,
        title: 'Reviewed generalized lesson',
        body: 'Human generalized text',
        generalization_reviewed: true,
      },
    };
    const action = {
      tool: 'prepare_closed_case_knowledge',
      arguments: {
        event_id: 8,
        source_digest: 'b'.repeat(64),
        ...input.knowledge,
      },
      can_prepare: true,
    };
    mocks.api.groupPreview.mockResolvedValueOnce({
      data: response('E', 'R03', [action]),
    });
    await wrapper
      .find('[data-testid="helpdesk-group-run-preview"]')
      .trigger('click');
    await flushPromises();
    await wrapper
      .find('[data-testid="helpdesk-draft-reviewed"]')
      .setValue(false);
    expect(
      wrapper.find('[data-testid="helpdesk-group-prepare"]').element.disabled
    ).toBe(true);
    await wrapper
      .find('[data-testid="helpdesk-group-prepare"]')
      .trigger('click');
    expect(mocks.api.groupPrepare).not.toHaveBeenCalled();
    expect(helpdeskDraftInput({ knowledge: input.knowledge })).toEqual(input);
    wrapper.unmount();
  });

  it('clears sources and human input on actor, account or event changes and ignores a late previous-context response', async () => {
    const wrapper = await page('R03');
    await loadChoices(wrapper, 'E', 'R03');
    await wrapper
      .find('[data-testid="helpdesk-draft-title"]')
      .setValue('Old human input');
    let finish;
    mocks.api.groupPreview.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    await wrapper
      .find('[data-testid="helpdesk-group-run-preview"]')
      .trigger('click');
    await wrapper.setProps({
      accountId: 13,
      contextKey: '13:8:administrator',
      event: { id: 9, ticket_id: 22, rule_key: 'R03' },
    });
    finish({ data: response('E', 'R03') });
    await flushPromises();
    expect(
      wrapper.find('[data-testid="helpdesk-draft-closed-case"]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-testid="helpdesk-group-prepare"]').exists()
    ).toBe(false);
    mocks.api.groupPreview.mockResolvedValueOnce({
      data: {
        ...response('E', 'R03'),
        event_id: 9,
        source: { ticket_id: 22, unit_id: 3, rule_key: 'R03' },
      },
    });
    await wrapper
      .find('[data-testid="helpdesk-group-run-preview"]')
      .trigger('click');
    await flushPromises();
    expect(
      wrapper.find('[data-testid="helpdesk-draft-title"]').element.value
    ).toBe('');
    expect(
      wrapper.find('[data-testid="helpdesk-draft-reviewed"]').element.checked
    ).toBe(false);
    expect(mocks.api.groupPrepare).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('uses finite draft input and rejects malformed native choices without accepting publication fields', () => {
    expect(
      helpdeskDraftInput({
        campaign: {
          incident_id: '51',
          inbox_id: '62',
          name: 'Name',
          audience_type: 'all_contacts',
        },
        knowledge: {
          closed_transition_id: '73',
          title: 'Title',
          body: 'Body',
          approved: true,
          customer_visible: true,
        },
      })
    ).toEqual({
      campaign: { incident_id: 51, inbox_id: 62, name: 'Name' },
      knowledge: {
        closed_transition_id: 73,
        title: 'Title',
        body: 'Body',
        generalization_reviewed: false,
      },
    });
    expect(
      helpdeskDraftChoices({
        campaign: { incidents: [{ id: -1, title: 'Invalid' }], inboxes: [] },
      })
    ).toBeNull();
    expect(
      helpdeskDraftChoices({ knowledge: { closed_cases: 'not an array' } })
    ).toBeNull();
  });
});
