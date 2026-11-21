import { afterEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useIvrAudioReference } from './useIvrAudioReference';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    audioVersion: vi.fn(),
    audioAssets: vi.fn(),
    audioVersions: vi.fn(),
  },
}));
const version = (overrides = {}) => ({
  id: '21',
  audio_asset_id: '11',
  unit_id: '7',
  number: 1,
  sha256: 'a'.repeat(64),
  file_name: 'Synthetic.wav',
  ready: false,
  technical_verification: { id: '31', audio_version_id: '21', ready: true },
  ...overrides,
});
const reference = () => ({
  asset_id: '11',
  version_id: '21',
  sha256: 'a'.repeat(64),
});
const paged = (items, page = 1, pages = 1) => ({
  data: { items, meta: { page, pages } },
});
const mounted = [];
const setup = (initial = null) => {
  let picker;
  const accountId = ref('1');
  const unitId = ref('7');
  const selected = ref(initial);
  const wrapper = mount(
    defineComponent({
      setup() {
        picker = useIvrAudioReference({
          accountId,
          unitId,
          reference: selected,
        });
        return () => null;
      },
    })
  );
  mounted.push(wrapper);
  return { picker, accountId, unitId, selected, wrapper };
};
afterEach(() => {
  mounted.splice(0).forEach(wrapper => wrapper.unmount());
  vi.resetAllMocks();
});

describe('native local IVR audio selection', () => {
  it('does not query the library or grant access until an explicit selection is requested', () => {
    const { picker } = setup();
    expect(picker.choosing.value).toBe(false);
    expect(API.audioAssets).not.toHaveBeenCalled();
    expect(API.audioVersion).not.toHaveBeenCalled();
  });
  it('resolves the exact old pin rather than substituting the newest library version', async () => {
    API.audioVersion.mockResolvedValue({ data: { item: version() } });
    const { picker } = setup(reference());
    await flushPromises();
    expect(API.audioVersion).toHaveBeenCalledWith('1', '11', '21');
    expect(picker.pinned.value.id).toBe('21');
    expect(picker.pinned.value.ready).toBe(false);
    expect(API.audioAssets).not.toHaveBeenCalled();
  });
  it.each([
    { sha256: 'b'.repeat(64) },
    { id: '22' },
    { unit_id: '8' },
    {
      technical_verification: {
        id: '32',
        audio_version_id: '21',
        ready: false,
      },
    },
    {
      technical_verification: { id: '32', audio_version_id: '22', ready: true },
    },
  ])(
    'does not display a substituted, unavailable or differently scoped pin %j',
    async overrides => {
      API.audioVersion.mockResolvedValue({
        data: { item: version(overrides) },
      });
      const { picker } = setup(reference());
      await flushPromises();
      expect(picker.pinned.value).toBeNull();
      expect(picker.error.value).toBe('UNAVAILABLE');
    }
  );
  it('keeps search and both paginated native projections bounded to the current unit', async () => {
    API.audioAssets.mockResolvedValue(
      paged([{ id: '11', unit_id: '7', name: 'Synthetic' }], 2, 3)
    );
    API.audioVersions.mockResolvedValue(paged([version()], 3, 4));
    const { picker } = setup();
    picker.assets.q = 'Synthetic';
    await picker.loadAssets(2);
    await picker.loadVersions('11', 3);
    expect(API.audioAssets).toHaveBeenCalledWith('1', {
      unit_id: '7',
      q: 'Synthetic',
      page: 2,
      per_page: 20,
    });
    expect(API.audioVersions).toHaveBeenCalledWith('1', '11', {
      page: 3,
      per_page: 20,
    });
    expect(picker.assets.page).toBe(2);
    expect(picker.versions.page).toBe(3);
    expect(picker.candidate.value).toBeNull();
    picker.select('21');
    expect(picker.versionReference(picker.candidate.value)).toEqual(
      reference()
    );
  });
  it('cannot choose an unverified version or one outside the returned authorized history', async () => {
    API.audioVersions.mockResolvedValue(
      paged([version({ technical_verification: null })])
    );
    const { picker } = setup();
    await picker.loadVersions('11');
    picker.select('21');
    expect(picker.candidate.value).toBeNull();
    picker.select('999');
    expect(picker.candidate.value).toBeNull();
  });
  it('ignores late version and pin responses after a fast unit switch', async () => {
    let resolvePin;
    let resolveVersions;
    API.audioVersion
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            resolvePin = resolve;
          })
      )
      .mockRejectedValue(new Error('Denied in new unit'));
    API.audioVersions.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveVersions = resolve;
        })
    );
    const { picker, unitId } = setup(reference());
    const loading = picker.loadVersions('11');
    unitId.value = '8';
    await flushPromises();
    resolvePin({ data: { item: version() } });
    resolveVersions(paged([version()]));
    await loading;
    await flushPromises();
    expect(picker.pinned.value).toBeNull();
    expect(picker.versions.items).toEqual([]);
    expect(picker.candidate.value).toBeNull();
    expect(picker.error.value).toBe('UNAVAILABLE');
  });
  it('ignores an older search response and keeps the later requested page', async () => {
    let finish;
    API.audioAssets
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      )
      .mockResolvedValueOnce(paged([{ id: '12', unit_id: '7' }], 2, 2));
    const { picker } = setup();
    const first = picker.loadAssets();
    await picker.loadAssets(2);
    finish(paged([{ id: '11', unit_id: '7' }], 1, 2));
    await first;
    expect(picker.assets.page).toBe(2);
    expect(picker.assets.items[0].id).toBe('12');
  });
  it('discards cached metadata and candidates after a denied native request', async () => {
    API.audioVersion.mockResolvedValue({ data: { item: version() } });
    API.audioAssets.mockRejectedValue({ response: { status: 401 } });
    const { picker } = setup(reference());
    await flushPromises();
    expect(picker.pinned.value).not.toBeNull();
    picker.begin();
    await flushPromises();
    expect(picker.pinned.value).toBeNull();
    expect(picker.assets.items).toEqual([]);
    expect(picker.choosing.value).toBe(false);
    expect(picker.error.value).toBe('ERROR');
  });
  it('ignores responses after cancel or unmount without changing the persisted draft', async () => {
    let finish;
    API.audioAssets.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const { picker, selected, wrapper } = setup();
    picker.begin();
    picker.cancel();
    wrapper.unmount();
    finish(paged([{ id: '11', unit_id: '7' }]));
    await flushPromises();
    expect(picker.assets.items).toEqual([]);
    expect(selected.value).toBeNull();
  });
});
