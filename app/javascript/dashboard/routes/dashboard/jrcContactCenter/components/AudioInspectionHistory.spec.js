import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AudioInspectionHistory from './AudioInspectionHistory.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { audioInspections: vi.fn(), inspectAudioVersion: vi.fn() },
}));

const version = { id: '99', unit_id: '10', sha256: 'a'.repeat(64) };
const proof = {
  id: '100',
  audio_version_id: '99',
  unit_id: '10',
  expected_sha256: version.sha256,
  observed_sha256: version.sha256,
  attempt: 1,
  state: 'clean',
  probe_state: 'valid',
  observed_at: '2026-11-20T00:00:00Z',
  created_by_name: 'SYNTHETIC reviewer',
  ready: true,
  scanner_adapter: 'clamav-instream-v1',
  decoder_version: 'ffmpeg version SYNTHETIC fixture',
  metadata: {
    duration_ms: 12000,
    codec: 'pcm_s16le',
    content_type: 'audio/wav',
    sample_rate: 8000,
    channels: 1,
  },
};
const page = item => {
  const items = item.attempt === 1 ? [item] : [item, proof];
  return { data: { items, meta: { page: 1, pages: 1, total: items.length } } };
};
const fixture = () =>
  mount(AudioInspectionHistory, {
    props: {
      accountId: '1',
      assetId: '44',
      version: { ...version },
      canManage: true,
    },
    global: { stubs: { AudioVersionPreview: true } },
  });
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.resetAllMocks();
  API.audioInspections.mockResolvedValue(page(proof));
});

describe('current audio metadata events (transport fixtures, not native scanner proof)', () => {
  it('reports only explicitly loaded first-page observations with the complete source identity', async () => {
    const latest = { ...proof, id: '105', attempt: 6 };
    API.audioInspections.mockResolvedValueOnce({
      data: {
        items: [6, 5, 4, 3, 2].map(attempt => ({
          ...proof,
          id: String(99 + attempt),
          attempt,
        })),
        meta: { page: 1, pages: 2, total: 6 },
      },
    });
    const wrapper = fixture();
    expect(API.audioInspections).not.toHaveBeenCalled();
    expect(wrapper.emitted('latest')).toBeUndefined();
    await wrapper.get('[data-toggle-audio-inspections]').trigger('click');
    await flushPromises();
    expect(wrapper.emitted('latest').at(-1)[0]).toEqual({
      accountId: '1',
      assetId: '44',
      versionId: '99',
      unitId: '10',
      proof: latest,
    });
    const before = wrapper.emitted('latest').length;
    API.audioInspections.mockResolvedValueOnce({
      data: {
        items: [proof],
        meta: { page: 2, pages: 2, total: 6 },
      },
    });
    await wrapper.get('nav').findAll('button').at(-1).trigger('click');
    await flushPromises();
    expect(API.audioInspections).toHaveBeenLastCalledWith('1', '44', '99', {
      page: 2,
      per_page: 5,
    });
    expect(wrapper.emitted('latest')).toHaveLength(before);
  });

  it('invalidates metadata during an uncertain write and reports the real latest unavailable observation after the accepted reload', async () => {
    const wrapper = fixture();
    await wrapper.get('[data-toggle-audio-inspections]').trigger('click');
    await flushPromises();
    let finish;
    API.inspectAudioVersion.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    await wrapper.get('[data-inspect-audio-version]').trigger('click');
    expect(wrapper.emitted('latest').at(-1)[0].proof).toBeNull();
    const later = {
      ...proof,
      id: '101',
      attempt: 2,
      ready: false,
      state: 'unavailable',
      probe_state: 'not_run',
      decoder_version: null,
      metadata: {},
    };
    API.audioInspections.mockResolvedValueOnce(page(later));
    finish({ data: { account_id: '1', item: later } });
    await flushPromises();
    expect(wrapper.emitted('latest').at(-1)[0]).toMatchObject({
      accountId: '1',
      unitId: '10',
      versionId: '99',
      proof: later,
    });
    const current = wrapper.get('[data-audio-inspection="101"]');
    expect(
      current.get('[data-audio-inspection-state="unavailable"]').exists()
    ).toBe(true);
    expect(current.find('[data-audio-decoded-metadata]').exists()).toBe(false);
    expect(
      wrapper
        .get(
          '[data-audio-inspection="100"] [data-audio-inspection-state="verified"]'
        )
        .exists()
    ).toBe(true);
    expect(wrapper.find('audio-version-preview-stub').exists()).toBe(false);
  });

  it('does not emit an accepted old-profile observation after current permission was withdrawn', async () => {
    const wrapper = fixture();
    await wrapper.get('[data-toggle-audio-inspections]').trigger('click');
    await flushPromises();
    let finish;
    API.inspectAudioVersion.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    await wrapper.get('[data-inspect-audio-version]').trigger('click');
    const before = wrapper.emitted('latest').length;
    await wrapper.setProps({ canManage: false });
    finish({ data: { account_id: '1', item: proof } });
    await flushPromises();
    expect(wrapper.emitted('latest')).toHaveLength(before);
    expect(wrapper.find('[data-audio-inspection]').exists()).toBe(false);
    expect(
      wrapper.get('[data-toggle-audio-inspections]').attributes('disabled')
    ).toBeDefined();
  });
});
