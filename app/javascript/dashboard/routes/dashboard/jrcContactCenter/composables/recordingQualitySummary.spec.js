import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import messages from 'dashboard/i18n/locale/en/jrcContactCenter.json';
import { useScopedRecordings } from './useScopedRecordings';
import { validRecordingQualitySummary } from './recordingQualitySummary';
import RecordingQualitySummary from '../components/RecordingQualitySummary.vue';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    context: vi.fn(),
    recordings: vi.fn(),
    recordingQualityReport: vi.fn(),
  },
}));
const wrappers = [];
const report = () => ({
  account_id: '1',
  items: [
    {
      id: '11',
      call_session_id: '7',
      quality: {
        available: true,
        sentiment: 'positivo',
        quality_score: 0,
        observed_at: '2026-11-27T10:00:00Z',
      },
    },
  ],
  meta: { page: 1, per_page: 20, total: 22, pages: 2 },
  period: {
    from: '2026-11-20',
    to: '2026-11-27',
    timezone: 'America/Sao_Paulo',
  },
  observed_at: '2026-11-27T11:00:00Z',
  quality_summary: {
    universe: 22,
    analyzed: 20,
    without_analysis: 2,
    unclassified: 1,
    counts: { positivo: 10, neutro: 3, negativo: 6 },
    percentages: { positivo: 50, neutro: 15, negativo: 30 },
    denominator: 'latest_original_analyses',
    quality_measured: 10,
    quality_average: 0,
  },
});
const fixture = query => {
  const accountId = ref('1');
  const actorScope = ref('SYNTHETIC authorized listener');
  const routeQuery = ref({ preserved_module: 'yes', ...query });
  const replaceQuery = async value => {
    routeQuery.value = value;
  };
  let state;
  wrappers.push(
    mount(
      defineComponent({
        setup() {
          state = useScopedRecordings({
            accountId,
            actorScope,
            routeQuery,
            replaceQuery,
          });
          return () => h('div');
        },
      })
    )
  );
  return { state, accountId, actorScope, routeQuery };
};
beforeEach(() => {
  vi.resetAllMocks();
  API.context.mockResolvedValue({
    data: {
      account_id: '1',
      capabilities: { recordings_view: true, recordings_listen: true },
    },
  });
  API.recordingQualityReport.mockImplementation(async () => ({
    data: report(),
  }));
  API.recordings.mockImplementation(async () => {
    const data = report();
    delete data.quality_summary;
    delete data.observed_at;
    return { data };
  });
});
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
});

describe('native whole-period quality metrics within existing recordings', () => {
  it('uses the existing authorized filters and the complete server denominator rather than the visible page', async () => {
    const { state } = fixture({
      recordings_mode: 'quality',
      recordings_queue_id: '8',
      recordings_from: '2026-11-20',
    });
    await flushPromises();
    expect(state.qualitySummary.value.analyzed).toBe(20);
    expect(state.items.value).toHaveLength(1);
    expect(state.qualitySummary.value.quality_average).toBe(0);
    expect(API.recordingQualityReport).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({
        queue_id: '8',
        from: '2026-11-20',
        page: 1,
        sentiment: '',
      })
    );
    expect(API.recordings).not.toHaveBeenCalled();
  });

  it('persists sentiment selection and resets pagination without losing native filters or other module query parameters', async () => {
    const { state, routeQuery } = fixture({
      recordings_mode: 'quality',
      recordings_page: '2',
      recordings_queue_id: '8',
    });
    await flushPromises();
    await state.filterSentiment('negativo');
    await flushPromises();
    expect(routeQuery.value).toEqual({
      recordings_mode: 'quality',
      recordings_sentiment: 'negativo',
      recordings_queue_id: '8',
      preserved_module: 'yes',
    });
    expect(API.recordingQualityReport).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ page: 1, sentiment: 'negativo', queue_id: '8' })
    );
  });

  it('clears all native criteria and sentiment while retaining the selected quality view', async () => {
    const { state, routeQuery } = fixture({
      recordings_mode: 'quality',
      recordings_sentiment: 'negativo',
      recordings_page: '2',
      recordings_queue_id: '8',
    });
    await flushPromises();
    await state.clearFilters();
    await flushPromises();
    expect(routeQuery.value).toEqual({
      recordings_mode: 'quality',
      preserved_module: 'yes',
    });
    expect(state.sentiment.value).toBe('');
  });

  it('returns to the native recording list without any quality API request or hidden sentiment filter', async () => {
    const { state, routeQuery } = fixture({
      recordings_mode: 'quality',
      recordings_sentiment: 'positivo',
    });
    await flushPromises();
    API.recordingQualityReport.mockClear();
    await state.changeMode(false);
    await flushPromises();
    expect(routeQuery.value).toEqual({ preserved_module: 'yes' });
    expect(state.qualitySummary.value).toBeNull();
    expect(API.recordings).toHaveBeenCalledOnce();
    expect(API.recordingQualityReport).not.toHaveBeenCalled();
  });

  it('requires current listening capability before requesting quality data even when viewing recordings is allowed', async () => {
    API.context.mockResolvedValue({
      data: {
        account_id: '1',
        capabilities: { recordings_view: true, recordings_listen: false },
      },
    });
    const { state } = fixture({ recordings_mode: 'quality' });
    await flushPromises();
    expect(state.error.value).toBe('DENIED');
    expect(state.items.value).toEqual([]);
    expect(API.recordingQualityReport).not.toHaveBeenCalled();
  });

  it('synchronously withdraws quality data on an actor authority refresh and ignores the previous pending response', async () => {
    let late;
    API.recordingQualityReport.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          late = resolve;
        })
    );
    const { state, actorScope } = fixture({ recordings_mode: 'quality' });
    await flushPromises();
    API.context.mockResolvedValue({
      data: { account_id: '1', capabilities: { recordings_view: false } },
    });
    actorScope.value = 'SYNTHETIC revoked listener';
    expect(state.items.value).toEqual([]);
    expect(state.qualitySummary.value).toBeNull();
    await flushPromises();
    late({ data: report() });
    await flushPromises();
    expect(state.error.value).toBe('DENIED');
    expect(state.qualitySummary.value).toBeNull();
  });

  [
    [503, 'quality_summary_source_unavailable', 'QUALITY_UNAVAILABLE'],
    [409, 'quality_summary_source_changed', 'QUALITY_CHANGED'],
    [422, 'quality_summary_range_too_large', 'QUALITY_RANGE_TOO_LARGE'],
  ].forEach(([status, code, message]) => {
    it(`keeps ${code} distinct from a successful empty analysis universe`, async () => {
      API.recordingQualityReport.mockRejectedValue({
        response: { status, data: { error: code } },
      });
      const { state } = fixture({ recordings_mode: 'quality' });
      await flushPromises();
      expect(state.error.value).toBe(message);
      expect(state.items.value).toEqual([]);
      expect(state.qualitySummary.value).toBeNull();
      expect(state.capabilities.value.recordings_view).toBe(true);
    });
  });

  [
    { recordings_mode: ['quality'] },
    { recordings_mode: 'other' },
    { recordings_sentiment: 'negativo' },
    {
      recordings_mode: 'quality',
      recordings_sentiment: ['positivo', 'negativo'],
    },
  ].forEach(query => {
    it(`rejects malformed view or sentiment query ${JSON.stringify(query)} without broadening the requested list`, async () => {
      const { state } = fixture(query);
      await flushPromises();
      expect(state.error.value).toBe('ERROR');
      expect(API.context).not.toHaveBeenCalled();
      expect(API.recordingQualityReport).not.toHaveBeenCalled();
      expect(API.recordings).not.toHaveBeenCalled();
    });
  });
});

describe('native quality response integrity and usable original-recording filters', () => {
  it('validates real zero separately from unavailable scores and percentages', () => {
    const data = report();
    expect(
      validRecordingQualitySummary(data, data.items, data.meta.total)
    ).toBe(true);
    data.quality_summary.quality_average = null;
    expect(
      validRecordingQualitySummary(data, data.items, data.meta.total)
    ).toBe(false);
  });

  [
    summary => {
      summary.universe = 21;
    },
    summary => {
      summary.percentages.negativo = 31;
    },
    summary => {
      summary.counts.positivo = -1;
    },
    summary => {
      summary.denominator = 'visible_page';
    },
    summary => {
      summary.quality_average = 101;
    },
  ].forEach((mutate, index) => {
    it(`rejects contradictory native summary ${index + 1}`, () => {
      const data = report();
      mutate(data.quality_summary);
      expect(
        validRecordingQualitySummary(data, data.items, data.meta.total)
      ).toBe(false);
    });
  });

  it('renders real counts, missing classifications and a zero quality score without fabricated insights or criticality', async () => {
    const data = report();
    const wrapper = mount(RecordingQualitySummary, {
      props: {
        summary: data.quality_summary,
        sentiment: 'negativo',
        observedAt: data.observed_at,
      },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'en',
            messages: { en: messages },
          }),
        ],
      },
    });
    wrappers.push(wrapper);
    expect(
      wrapper.get('[data-quality-filter="negativo"]').attributes('aria-pressed')
    ).toBe('true');
    expect(wrapper.get('[data-quality-filter="negativo"]').text()).toContain(
      '30%'
    );
    expect(wrapper.get('[data-quality-denominator]').text()).toContain(
      '20 análises'
    );
    expect(wrapper.get('[data-quality-score]').text()).toContain(
      'qualidade: 0'
    );
    expect(wrapper.text()).toContain(
      'Sentimento negativo não indica criticidade'
    );
    await wrapper
      .get('[data-quality-filter="without_analysis"]')
      .trigger('click');
    expect(wrapper.emitted('filter')).toEqual([['without_analysis']]);
  });
});
