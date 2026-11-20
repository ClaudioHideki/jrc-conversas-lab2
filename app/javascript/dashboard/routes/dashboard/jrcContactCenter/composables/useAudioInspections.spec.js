import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useAudioInspections } from './useAudioInspections';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { audioInspections: vi.fn(), inspectAudioVersion: vi.fn() },
}));

const source = { id: '99', unit_id: '10', sha256: 'a'.repeat(64) };
const item = {
  id: '100',
  audio_version_id: '99',
  unit_id: '10',
  attempt: 1,
  expected_sha256: source.sha256,
  state: 'unavailable',
  probe_state: 'not_run',
  ready: false,
};
const receipt = value => ({ data: { account_id: '1', item: value } });
const history = (items = [], page = 1, pages = 1) => ({
  data: { items, meta: { page, pages, total: pages * 5 } },
});
const fixture = () => {
  const accountId = ref('1');
  const assetId = ref('44');
  const version = ref({ ...source });
  const canManage = ref(true);
  const onDenied = vi.fn();
  let state;
  mount(
    defineComponent({
      setup() {
        state = useAudioInspections({
          accountId,
          assetId,
          version,
          canManage,
          onDenied,
        });
        return () => null;
      },
    })
  );
  return { state, accountId, assetId, version, canManage, onDenied };
};

enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  API.audioInspections.mockResolvedValue(history());
  API.inspectAudioVersion.mockResolvedValue(receipt(item));
});

describe('exact-version technical receipt UI (dependency fixtures, not native scanner proof)', () => {
  it('loads only the deliberately opened version and uses bounded native history pages', async () => {
    const { state } = fixture();
    expect(API.audioInspections).not.toHaveBeenCalled();
    state.open();
    await flushPromises();
    expect(API.audioInspections).toHaveBeenCalledWith('1', '44', '99', {
      page: 1,
      per_page: 5,
    });
    state.page.value = 2;
    await flushPromises();
    expect(API.audioInspections).toHaveBeenLastCalledWith('1', '44', '99', {
      page: 2,
      per_page: 5,
    });
  });

  it('prevents concurrent writes and reloads server history instead of fabricating a clean row', async () => {
    let complete;
    API.inspectAudioVersion.mockReturnValueOnce(
      new Promise(resolve => {
        complete = resolve;
      })
    );
    API.audioInspections.mockResolvedValue(history([item]));
    const { state } = fixture();
    state.open();
    await flushPromises();
    const pending = state.inspect();
    await state.inspect();
    expect(API.inspectAudioVersion).toHaveBeenCalledOnce();
    expect(state.saving.value).toBe(true);
    complete(receipt(item));
    await pending;
    expect(state.items.value).toEqual([item]);
    expect(state.items.value[0].ready).toBe(false);
    expect(state.saving.value).toBe(false);
  });

  it('reuses the exact request key after an uncertain response and allocates a new one only after confirmed receipt', async () => {
    API.inspectAudioVersion.mockRejectedValueOnce(
      new Error('SYNTHETIC lost response')
    );
    const { state } = fixture();
    await state.inspect();
    expect(state.error.value).toBe('UNCERTAIN');
    const first = API.inspectAudioVersion.mock.calls[0][3];
    await state.inspect();
    expect(API.inspectAudioVersion.mock.calls[1][3]).toBe(first);
    await state.inspect();
    expect(API.inspectAudioVersion.mock.calls[2][3]).not.toBe(first);
  });

  it.each([
    { ...item, audio_version_id: '101' },
    { ...item, unit_id: '11' },
    { ...item, expected_sha256: 'b'.repeat(64) },
    { ...item, attempt: 0 },
  ])(
    'does not accept a receipt for another source or an invalid sequence: %o',
    async value => {
      API.inspectAudioVersion.mockResolvedValueOnce(receipt(value));
      const { state } = fixture();
      await state.inspect();
      expect(state.error.value).toBe('UNCERTAIN');
      const key = API.inspectAudioVersion.mock.calls[0][3];
      await state.inspect();
      expect(API.inspectAudioVersion.mock.calls[1][3]).toBe(key);
      expect(state.items.value).toEqual([]);
    }
  );

  it('drops private history and late responses on source change instead of mixing versions', async () => {
    let complete;
    API.audioInspections.mockReturnValueOnce(
      new Promise(resolve => {
        complete = resolve;
      })
    );
    const { state, version } = fixture();
    state.open();
    version.value = { id: '101', unit_id: '11', sha256: 'b'.repeat(64) };
    await flushPromises();
    complete(history([item]));
    await flushPromises();
    expect(state.items.value).toEqual([]);
    expect(state.opened.value).toBe(false);
    expect(state.loading.value).toBe(false);
  });

  it('clears on native denied responses and does not keep displaying earlier authorized data', async () => {
    API.audioInspections.mockResolvedValueOnce(history([item]));
    API.inspectAudioVersion.mockRejectedValueOnce({
      response: { status: 401 },
    });
    const { state, onDenied } = fixture();
    state.open();
    await flushPromises();
    expect(state.items.value).toEqual([item]);
    await state.inspect();
    expect(onDenied).toHaveBeenCalledOnce();
    expect(state.items.value).toEqual([]);
    expect(state.opened.value).toBe(false);
    expect(state.saving.value).toBe(false);
  });

  it('does not write after management capability is withdrawn and discards the previous scope', async () => {
    const { state, canManage } = fixture();
    state.open();
    await flushPromises();
    canManage.value = false;
    await flushPromises();
    await state.inspect();
    expect(API.inspectAudioVersion).not.toHaveBeenCalled();
    expect(state.items.value).toEqual([]);
    expect(state.opened.value).toBe(false);
  });
});
