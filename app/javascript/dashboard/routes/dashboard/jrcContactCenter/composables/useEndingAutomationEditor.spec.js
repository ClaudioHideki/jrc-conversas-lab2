import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useEndingAutomationEditor } from './useEndingAutomationEditor';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    acwPolicy: vi.fn(),
    endingRules: vi.fn(),
    endingRuleSourceContext: vi.fn(),
    saveEndingRule: vi.fn(),
  },
}));
enableAutoUnmount(afterEach);
const original = 'a'.repeat(64);
const refreshed = 'b'.repeat(64);
const stored = () => ({
  code: 'SYNTHETIC_RULE',
  name: 'SYNTHETIC private rule',
  reason_code: 'SYNTHETIC_REASON',
  queue_id: '8',
  timing: 'call_end',
  execution_mode: 'automatic',
  active: true,
  conditions: { outcome_codes: [] },
  scope: {
    integrity_sha256: original,
    queue_scope_version_id: '9',
    unit_id: '7',
    issuer_company_id: '5',
    business_unit_id: '6',
  },
  actions: [
    {
      kind: 'project_task',
      parameters: {
        project_id: '10',
        due_after_days: null,
        attributes: {
          title: 'SYNTHETIC private task',
          priority: 'medium',
          board_column_id: '11',
          estimated_minutes: 0,
        },
      },
    },
  ],
});
const listed = (rows = [stored()], account = '1', revision = original) => ({
  data: {
    account_id: account,
    items: rows,
    revision,
    configuration_only: true,
    execution_available: false,
    meta: {
      page: 1,
      per_page: 10,
      total: rows.length,
      pages: rows.length ? 1 : 0,
    },
  },
});
const policy = (account = '1', revision = original) => ({
  data: {
    item: {
      id: account,
      revision,
      voice_reason_catalog: {
        version: 1,
        entries: [
          { code: 'SYNTHETIC_REASON', name: 'SYNTHETIC reason', active: true },
        ],
      },
    },
  },
});
const source = (account = '1', id = '8', revision = original) => ({
  data: {
    account_id: account,
    item: {
      id,
      name: 'SYNTHETIC queue',
      unit: { id: '7', name: 'SYNTHETIC unit' },
      scope_revision: revision,
      configuration_available: true,
      execution_available: false,
    },
  },
});
const mountEditor = () => {
  const accountId = ref('1');
  let editor;
  const wrapper = mount(
    defineComponent({
      setup() {
        editor = useEndingAutomationEditor({ accountId });
        return () => h('div');
      },
    })
  );
  return { wrapper, accountId, editor };
};
const deferred = () => {
  let resolve;
  const promise = new Promise(done => {
    resolve = done;
  });
  return { promise, resolve };
};
beforeEach(() => {
  vi.clearAllMocks();
  API.acwPolicy.mockResolvedValue(policy());
  API.endingRules.mockResolvedValue(listed());
  API.endingRuleSourceContext.mockResolvedValue(source());
  API.saveEndingRule.mockResolvedValue({
    data: { account_id: '1', revision: refreshed, item: stored() },
  });
});

describe('authorized operational ending-rule editor', () => {
  it('pins activation to the actual displayed saved rule when a background list refresh sees a newer definition', async () => {
    const { editor } = mountEditor();
    await flushPromises();
    await editor.edit(editor.items.value[0]);
    const newer = {
      ...stored(),
      name: 'SYNTHETIC newer unreviewed definition',
    };
    API.acwPolicy.mockResolvedValueOnce(policy('1', refreshed));
    API.endingRules.mockResolvedValueOnce(listed([newer], '1', refreshed));
    await editor.load();
    expect(editor.items.value[0].name).toBe(newer.name);
    expect(editor.draft.value.name).toBe('SYNTHETIC private rule');
    expect(editor.activationRevision.value).toBe(original);
    expect(API.saveEndingRule).not.toHaveBeenCalled();
  });

  it('keeps activation on the displayed snapshot through conflict review and advances it only after a reviewed save', async () => {
    const { editor } = mountEditor();
    await flushPromises();
    await editor.edit(editor.items.value[0]);
    editor.revision.handleError({
      response: { data: { error: 'stale_configuration_revision' } },
    });
    API.endingRules.mockResolvedValueOnce(listed([stored()], '1', refreshed));
    await editor.revision.reload();
    expect(editor.revision.state.expected).toBe(refreshed);
    expect(editor.activationRevision.value).toBe(original);
    editor.draft.value.name = 'SYNTHETIC explicitly chosen definition';
    await flushPromises();
    editor.reviewConflict(true);
    editor.reviewed.value = true;
    const savedRevision = 'c'.repeat(64);
    API.saveEndingRule.mockResolvedValueOnce({
      data: {
        account_id: '1',
        revision: savedRevision,
        item: { ...stored(), name: editor.draft.value.name },
      },
    });
    await editor.save();
    expect(API.saveEndingRule).toHaveBeenCalledTimes(1);
    expect(API.saveEndingRule.mock.calls[0][2]).toBe(refreshed);
    expect(editor.activationRevision.value).toBe(savedRevision);
  });

  it('permits a reviewed inactive draft without a destination while keeping an active empty rule blocked', async () => {
    const { editor } = mountEditor();
    await flushPromises();
    await editor.edit(null);
    Object.assign(editor.draft.value, {
      code: 'SYNTHETIC_DRAFT',
      name: 'SYNTHETIC draft',
      reason_code: 'SYNTHETIC_REASON',
      timing: 'call_end',
      execution_mode: 'agent_confirmation',
    });
    await editor.selectQueue('8');
    await flushPromises();
    editor.reviewed.value = true;
    expect(editor.canSave.value).toBe(true);
    editor.draft.value.active = true;
    await flushPromises();
    editor.reviewed.value = true;
    expect(editor.canSave.value).toBe(false);
    expect(API.saveEndingRule).not.toHaveBeenCalled();
  });
  it('treats a real rule named __new__ as persisted during conflict review instead of substituting an empty new draft', async () => {
    const row = { ...stored(), code: '__new__' };
    API.endingRules.mockResolvedValue(listed([row]));
    const { editor } = mountEditor();
    await flushPromises();
    await editor.edit(editor.items.value[0]);
    editor.revision.handleError({
      response: { data: { error: 'stale_configuration_revision' } },
    });
    await editor.revision.reload();
    expect(API.endingRules).toHaveBeenLastCalledWith('1', {
      rule_code: '__new__',
      page: 1,
      per_page: 1,
    });
    expect(editor.revision.state.latest.name).toBe('SYNTHETIC private rule');
    expect(editor.revision.state.latest.code).toBe('__new__');
    expect(editor.draft.value.name).toBe('SYNTHETIC private rule');
  });
  it('loads the native private list with bounded pagination and does not execute its destination', async () => {
    const { editor } = mountEditor();
    await flushPromises();
    expect(editor.items.value[0].code).toBe('SYNTHETIC_RULE');
    expect(API.endingRules).toHaveBeenCalledWith('1', {
      q: '',
      status: 'all',
      page: 1,
      per_page: 10,
    });
    expect(API.saveEndingRule).not.toHaveBeenCalled();
    expect(editor.draft.value).toBeNull();
  });

  it('requires an explicit execution mode for a new rule instead of assuming automation is automatic', async () => {
    const { editor } = mountEditor();
    await flushPromises();
    await editor.edit(null);
    expect(editor.draft.value.execution_mode).toBe('');
    expect(editor.draft.value.timing).toBe('');
    expect(editor.draft.value.active).toBe(false);
    expect(editor.canSave.value).toBe(false);
  });

  it('keeps legacy versions unselected until the operator explicitly reviews the new mode', async () => {
    const legacy = stored();
    delete legacy.execution_mode;
    API.endingRules.mockResolvedValue(listed([legacy]));
    const { editor } = mountEditor();
    await flushPromises();
    await editor.edit(editor.items.value[0]);
    editor.draft.value.name = 'SYNTHETIC reviewed';
    await flushPromises();
    editor.reviewed.value = true;
    expect(editor.draft.value.execution_mode).toBe('');
    expect(editor.canSave.value).toBe(false);
    expect(legacy).not.toHaveProperty('execution_mode');
  });

  it('saves only the reviewed native version, exact source hash and explicit mode without granting authority through identifiers', async () => {
    const { editor } = mountEditor();
    await flushPromises();
    await editor.edit(editor.items.value[0]);
    editor.draft.value.name = 'SYNTHETIC reviewed';
    editor.draft.value.execution_mode = 'agent_confirmation';
    await flushPromises();
    expect(editor.canSave.value).toBe(false);
    editor.reviewed.value = true;
    await editor.save();
    expect(API.saveEndingRule).toHaveBeenCalledOnce();
    const [account, document, revision] = API.saveEndingRule.mock.calls[0];
    expect({ account, revision }).toEqual({ account: '1', revision: original });
    expect(document).toMatchObject({
      scope_revision: original,
      execution_mode: 'agent_confirmation',
    });
    expect(document).not.toHaveProperty('scope');
    expect(document).not.toHaveProperty('user_id');
    expect(editor.saved.value).toBe(true);
  });

  it('prevents duplicate saves while the first request is unresolved', async () => {
    const pending = deferred();
    API.saveEndingRule.mockReturnValueOnce(pending.promise);
    const { editor } = mountEditor();
    await flushPromises();
    await editor.edit(editor.items.value[0]);
    editor.draft.value.name = 'SYNTHETIC changed';
    await flushPromises();
    editor.reviewed.value = true;
    const first = editor.save();
    await editor.save();
    expect(API.saveEndingRule).toHaveBeenCalledOnce();
    pending.resolve({
      data: { account_id: '1', revision: refreshed, item: stored() },
    });
    await first;
    expect(editor.saving.value).toBe(false);
  });

  it('invalidates the explicit review when any draft value changes', async () => {
    const { editor } = mountEditor();
    await flushPromises();
    await editor.edit(editor.items.value[0]);
    editor.draft.value.name = 'SYNTHETIC changed';
    await flushPromises();
    editor.reviewed.value = true;
    expect(editor.canSave.value).toBe(true);
    editor.draft.value.active = false;
    await flushPromises();
    expect(editor.reviewed.value).toBe(false);
    expect(editor.canSave.value).toBe(false);
  });

  it('keeps a stale local draft and requires comparison plus manual review of the refreshed source', async () => {
    API.saveEndingRule.mockRejectedValueOnce({
      response: {
        status: 409,
        data: { error: 'stale_configuration_revision' },
      },
    });
    const { editor } = mountEditor();
    await flushPromises();
    await editor.edit(editor.items.value[0]);
    editor.draft.value.name = 'SYNTHETIC local value';
    await flushPromises();
    editor.reviewed.value = true;
    await editor.save();
    expect(editor.revision.state.conflict).toBe(true);
    expect(editor.draft.value.name).toBe('SYNTHETIC local value');
    API.endingRules.mockResolvedValueOnce(listed([stored()], '1', refreshed));
    API.endingRuleSourceContext.mockResolvedValueOnce(
      source('1', '8', refreshed)
    );
    await editor.revision.reload();
    expect(API.endingRules).toHaveBeenLastCalledWith('1', {
      rule_code: 'SYNTHETIC_RULE',
      page: 1,
      per_page: 1,
    });
    expect(editor.draft.value.scope_revision).toBe(original);
    expect(editor.canSave.value).toBe(false);
    editor.reviewConflict(true);
    await flushPromises();
    editor.reviewed.value = true;
    expect(editor.draft.value.scope_revision).toBe(refreshed);
    expect(editor.canSave.value).toBe(true);
  });

  it('preserves an uncertain network result but blocks a blind second request', async () => {
    API.saveEndingRule.mockRejectedValueOnce(
      new Error('SYNTHETIC network unavailable')
    );
    const { editor } = mountEditor();
    await flushPromises();
    await editor.edit(editor.items.value[0]);
    editor.draft.value.name = 'SYNTHETIC preserved';
    await flushPromises();
    editor.reviewed.value = true;
    await editor.save();
    expect(editor.error.value).toBe('SAVE_FAILED');
    expect(editor.draft.value.name).toBe('SYNTHETIC preserved');
    await editor.save();
    expect(API.saveEndingRule).toHaveBeenCalledOnce();
  });

  it.each([401, 403, 404])(
    'removes private templates after a real HTTP%i denial during saving',
    async status => {
      API.saveEndingRule.mockRejectedValueOnce({ response: { status } });
      const { editor } = mountEditor();
      await flushPromises();
      await editor.edit(editor.items.value[0]);
      editor.draft.value.active = false;
      await flushPromises();
      editor.reviewed.value = true;
      await editor.save();
      expect(editor.error.value).toBe('DENIED');
      expect(editor.draft.value).toBeNull();
      expect(editor.items.value).toEqual([]);
      expect(editor.source.value).toBeNull();
    }
  );

  it('ignores a late private list from the previous account after a quick account switch', async () => {
    const pending = deferred();
    API.endingRules.mockReturnValueOnce(pending.promise);
    const { editor, accountId } = mountEditor();
    await flushPromises();
    API.acwPolicy.mockResolvedValueOnce(policy('2'));
    API.endingRules.mockResolvedValueOnce(listed([], '2'));
    accountId.value = '2';
    await flushPromises();
    pending.resolve(listed());
    await flushPromises();
    expect(editor.items.value).toEqual([]);
    expect(editor.draft.value).toBeNull();
    expect(editor.error.value).toBe('');
  });

  it('ignores a late queue scope and clears a pending source spinner when the selection is removed', async () => {
    const { editor } = mountEditor();
    await flushPromises();
    await editor.edit(null);
    const pending = deferred();
    API.endingRuleSourceContext.mockReturnValueOnce(pending.promise);
    const first = editor.selectQueue('8');
    await editor.selectQueue('');
    pending.resolve(source());
    await first;
    expect(editor.source.value).toBeNull();
    expect(editor.draft.value.scope_revision).toBe('');
    expect(editor.sourceLoading.value).toBe(false);
  });

  it('does not combine a rule list with a policy from a different revision', async () => {
    API.endingRules.mockResolvedValueOnce(listed([stored()], '1', refreshed));
    const { editor } = mountEditor();
    await flushPromises();
    expect(editor.error.value).toBe('LOAD_FAILED');
    expect(editor.items.value).toEqual([]);
    await editor.edit(null);
    expect(editor.draft.value).toBeNull();
  });

  it('keeps an authorized closed source available for deactivation while forbidding activation', async () => {
    const response = source();
    response.data.item.configuration_available = false;
    API.endingRuleSourceContext.mockResolvedValue(response);
    const { editor } = mountEditor();
    await flushPromises();
    await editor.edit(editor.items.value[0]);
    editor.draft.value.name = 'SYNTHETIC updated';
    await flushPromises();
    editor.reviewed.value = true;
    expect(editor.canSave.value).toBe(false);
    editor.draft.value.active = false;
    await flushPromises();
    editor.reviewed.value = true;
    expect(editor.canSave.value).toBe(true);
  });
});
