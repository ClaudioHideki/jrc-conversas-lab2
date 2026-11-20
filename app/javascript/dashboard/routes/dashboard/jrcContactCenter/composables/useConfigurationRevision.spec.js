import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useConfigurationRevision } from './useConfigurationRevision';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { configurationRecord: vi.fn(), acwPolicy: vi.fn() },
}));
const original = 'a'.repeat(64);
const refreshed = 'b'.repeat(64);
const conflict = code => ({ response: { data: { error: code } } });
const mountRevision = (onDenied = undefined) => {
  const accountId = ref('1');
  const resource = ref('queues');
  const draft = ref({ name: 'Preserved local draft' });
  let revision;
  const wrapper = mount(
    defineComponent({
      setup() {
        revision = useConfigurationRevision({
          accountId,
          resource,
          draft,
          onDenied,
        });
        return () => h('div');
      },
    })
  );
  return { wrapper, revision, accountId, resource, draft };
};
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  API.configurationRecord.mockResolvedValue({
    data: { item: { id: 10, revision: refreshed, name: 'Concurrent state' } },
  });
});

describe('expected configuration revision lifecycle', () => {
  it.each([401, 403, 404])(
    'invokes private context cleanup on an explicit%i during native audio revision reload',
    async status => {
      const denied = vi.fn();
      const { revision, resource } = mountRevision(denied);
      resource.value = 'audio_assets';
      await flushPromises();
      revision.capture({ id: '44', revision: original });
      revision.handleError(conflict('stale_configuration_revision'));
      API.configurationRecord.mockRejectedValueOnce({ response: { status } });
      await revision.reload();
      expect(denied).toHaveBeenCalledOnce();
      expect(revision.state.latest).toBeNull();
      expect(API.configurationRecord).toHaveBeenCalledWith(
        '1',
        'audio_assets',
        '44'
      );
    }
  );
  it('requires the exact native revision for institutional folder edits and conflict reloads', async () => {
    const { revision, resource } = mountRevision();
    resource.value = 'audio_folders';
    await flushPromises();
    revision.capture({ id: 10, revision: original });
    expect(revision.state.required).toBe(true);
    expect(revision.options()).toEqual({ expected_revision: original });
    expect(revision.handleError(conflict('stale_configuration_revision'))).toBe(
      true
    );
    await revision.reload();
    expect(API.configurationRecord).toHaveBeenCalledWith(
      '1',
      'audio_folders',
      10
    );
    expect(revision.canSave.value).toBe(false);
    revision.review(true);
    expect(revision.options()).toEqual({ expected_revision: refreshed });
  });

  it('blocks an old captured context immediately when account or resource changes', () => {
    const { revision, accountId, resource } = mountRevision();
    revision.capture({ id: 10, revision: original });
    expect(revision.canSave.value).toBe(true);
    accountId.value = '2';
    expect(revision.canSave.value).toBe(false);
    revision.capture({ id: 10, revision: refreshed });
    expect(revision.canSave.value).toBe(true);
    resource.value = 'memberships';
    expect(revision.canSave.value).toBe(false);
  });

  it('preserves creation and unrelated native team workflows without an invented precondition', () => {
    const { revision, resource } = mountRevision();
    revision.capture(null);
    expect(revision.options()).toEqual({});
    expect(revision.canSave.value).toBe(true);
    resource.value = 'teams';
    revision.capture({ id: 10 });
    expect(revision.state.required).toBe(false);
    expect(revision.options()).toEqual({});
  });

  it('captures and submits the revision belonging to the loaded record', () => {
    const { revision } = mountRevision();
    revision.capture({ id: 10, revision: original });
    expect(revision.options()).toEqual({ expected_revision: original });
    expect(revision.canSave.value).toBe(true);
  });

  it('blocks a missing revision rather than silently using the legacy API path', async () => {
    const { revision } = mountRevision();
    revision.capture({ id: 10 });
    expect(revision.canSave.value).toBe(false);
    await revision.reload();
    expect(revision.canSave.value).toBe(false);
    revision.review(true);
    expect(revision.canSave.value).toBe(true);
    expect(revision.options()).toEqual({ expected_revision: refreshed });
  });

  it('retains the draft through conflict and requires a reviewed fresh state before retry', async () => {
    const { revision, draft } = mountRevision();
    revision.capture({ id: 10, revision: original });
    expect(revision.handleError(conflict('stale_configuration_revision'))).toBe(
      true
    );
    expect(revision.canSave.value).toBe(false);
    await revision.reload();
    expect(API.configurationRecord).toHaveBeenCalledWith('1', 'queues', 10);
    expect(draft.value.name).toBe('Preserved local draft');
    expect(revision.state.latest.name).toBe('Concurrent state');
    expect(revision.canSave.value).toBe(false);
    revision.review(true);
    expect(revision.canSave.value).toBe(true);
    draft.value.name = 'Changed after reviewing';
    expect(revision.canSave.value).toBe(false);
    revision.review(true);
    expect(revision.canSave.value).toBe(true);
  });

  it('keeps a permission-rejected reload blocked without deleting the user input', async () => {
    API.configurationRecord.mockRejectedValue({ response: { status: 404 } });
    const { revision, draft } = mountRevision();
    revision.capture({ id: 10, revision: original });
    revision.handleError(conflict('stale_configuration_revision'));
    await revision.reload();
    expect(revision.state.error).toBe(true);
    expect(revision.state.latest).toBeNull();
    expect(revision.canSave.value).toBe(false);
    expect(draft.value.name).toBe('Preserved local draft');
  });

  it('discards a late reload from a previous account', async () => {
    let finish;
    API.configurationRecord.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const { revision, accountId } = mountRevision();
    revision.capture({ id: 10, revision: original });
    revision.handleError(conflict('stale_configuration_revision'));
    const pending = revision.reload();
    accountId.value = '2';
    await flushPromises();
    finish({
      data: {
        item: { id: 10, revision: refreshed, name: 'PRIVATE old account' },
      },
    });
    await pending;
    expect(revision.state.latest).toBeNull();
    expect(revision.state.expected).toBe('');
    expect(revision.state.required).toBe(false);
  });

  it('discards a late response after opening another record', async () => {
    let finish;
    API.configurationRecord.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const { revision } = mountRevision();
    revision.capture({ id: 10, revision: original });
    const pending = revision.reload();
    revision.capture({ id: 11, revision: original });
    finish({
      data: { item: { id: 10, revision: refreshed, name: 'Previous record' } },
    });
    await pending;
    expect(revision.state.id).toBe(11);
    expect(revision.state.latest).toBeNull();
    expect(revision.state.expected).toBe(original);
  });

  it('rejects malformed response identity or revision instead of accepting an unverified state', async () => {
    API.configurationRecord.mockResolvedValue({
      data: { item: { id: 999, revision: 'invalid' } },
    });
    const { revision } = mountRevision();
    revision.capture({ id: 10, revision: original });
    revision.handleError(conflict('stale_configuration_revision'));
    await revision.reload();
    expect(revision.state.error).toBe(true);
    expect(revision.state.latest).toBeNull();
    expect(revision.canSave.value).toBe(false);
  });

  it('treats a missing server precondition as a review conflict without weakening the API', () => {
    const { revision } = mountRevision();
    revision.capture({ id: 10, revision: original });
    expect(
      revision.handleError(conflict('configuration_revision_required'))
    ).toBe(true);
    expect(revision.canSave.value).toBe(false);
    expect(revision.state.conflict).toBe(true);
  });

  it('leaves validation and authorization failures to the existing error flow', () => {
    const { revision } = mountRevision();
    revision.capture({ id: 10, revision: original });
    expect(revision.handleError(conflict('inactive_queue'))).toBe(false);
    expect(revision.state.conflict).toBe(false);
    expect(revision.canSave.value).toBe(true);
  });
});

describe('local IVR immutable revision support', () => {
  it('uses positive integer revisions only for the local IVR resource', async () => {
    const { revision, resource } = mountRevision();
    resource.value = 'ivr_drafts';
    await flushPromises();
    revision.capture({ id: '10', revision: 1 });
    expect(revision.canSave.value).toBe(true);
    expect(revision.options()).toEqual({ expected_revision: 1 });
    revision.capture({ id: '10', revision: '1' });
    expect(revision.canSave.value).toBe(false);
    resource.value = 'queues';
    await flushPromises();
    revision.capture({ id: '10', revision: 1 });
    expect(revision.canSave.value).toBe(false);
  });

  it('preserves the local graph across a stale revision and invalidates review when it is edited', async () => {
    const { revision, resource, draft } = mountRevision();
    resource.value = 'ivr_drafts';
    await flushPromises();
    draft.value.definition = {
      schema_version: 1,
      start: 'end',
      nodes: [{ id: 'end', type: 'end' }],
    };
    revision.capture({ id: '10', revision: 1 });
    API.configurationRecord.mockResolvedValue({
      data: { item: { id: '10', revision: 2, name: 'SYNTHETIC concurrent' } },
    });
    expect(revision.handleError(conflict('stale_ivr_revision'))).toBe(true);
    await revision.reload();
    expect(API.configurationRecord).toHaveBeenCalledWith(
      '1',
      'ivr_drafts',
      '10'
    );
    expect(draft.value.definition.start).toBe('end');
    expect(revision.canSave.value).toBe(false);
    revision.review(true);
    expect(revision.options()).toEqual({ expected_revision: 2 });
    expect(revision.canSave.value).toBe(true);
    draft.value.definition.start = 'other';
    expect(revision.canSave.value).toBe(false);
  });

  it('does not adopt configuration SHA tokens as immutable IVR revision numbers', async () => {
    const { revision, resource } = mountRevision();
    resource.value = 'ivr_drafts';
    await flushPromises();
    revision.capture({ id: '10', revision: 1 });
    API.configurationRecord.mockResolvedValue({
      data: { item: { id: '10', revision: refreshed } },
    });
    revision.handleError(conflict('stale_ivr_revision'));
    await revision.reload();
    revision.review(true);
    expect(revision.canSave.value).toBe(false);
    expect(revision.state.error).toBe(true);
  });

  it('does not treat native queue revision errors as local IVR conflicts or vice versa', async () => {
    const { revision, resource } = mountRevision();
    revision.capture({ id: 10, revision: original });
    expect(revision.handleError(conflict('stale_ivr_revision'))).toBe(false);
    resource.value = 'ivr_drafts';
    await flushPromises();
    revision.capture({ id: '10', revision: 1 });
    expect(revision.handleError(conflict('stale_configuration_revision'))).toBe(
      false
    );
    expect(revision.handleError(conflict('ivr_revision_required'))).toBe(true);
  });
});

describe('native global ACW snapshot', () => {
  it('uses the real ACW endpoint and rejects an account-mismatched reload', async () => {
    const { revision, resource } = mountRevision();
    resource.value = 'acw_policy';
    await flushPromises();
    revision.capture({ id: '1', revision: original });
    API.acwPolicy.mockResolvedValueOnce({
      data: { item: { id: '2', revision: refreshed } },
    });
    revision.handleError(conflict('stale_configuration_revision'));
    await revision.reload();
    expect(API.acwPolicy).toHaveBeenCalledWith('1');
    expect(revision.state.error).toBe(true);
    expect(revision.state.latest).toBeNull();
    expect(revision.canSave.value).toBe(false);
  });
  it('requires a reviewed ACW draft and never treats a revision as an authority grant', async () => {
    const { revision, resource, draft } = mountRevision();
    resource.value = 'acw_policy';
    await flushPromises();
    draft.value = { voice: 120, whatsapp: 180, voice_required: false };
    revision.capture({ id: '1', revision: original });
    API.acwPolicy.mockResolvedValueOnce({
      data: {
        item: {
          id: '1',
          revision: refreshed,
          limits: { voice: 300, whatsapp: 180 },
        },
      },
    });
    revision.handleError(conflict('stale_configuration_revision'));
    await revision.reload();
    expect(draft.value.voice).toBe(120);
    expect(revision.canSave.value).toBe(false);
    revision.review(true);
    expect(revision.options()).toEqual({ expected_revision: refreshed });
    expect(revision.canSave.value).toBe(true);
    draft.value.voice_required = true;
    expect(revision.canSave.value).toBe(false);
  });
});
