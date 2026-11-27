import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import RecordingAnalysis from './RecordingAnalysis.vue';

const api = vi.hoisted(() => ({ qualityReview: vi.fn() }));
vi.mock('dashboard/api/jrcContactCenter', () => ({ default: api }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
enableAutoUnmount(afterEach);
const body = () => ({
  account_id: '1',
  recording_id: '15',
  source_sha256: 'a'.repeat(64),
  can_review: false,
  revision: 0,
  latest_review: null,
  original: {
    sentimento_cliente: 'positivo',
    nota_final: 0,
    sentiment_confidence: null,
    model: null,
    resumo_conversa: 'SYNTHETIC original <img src=x onerror=alert(1)>',
    themes: ['SYNTHETIC theme'],
    recommendations: [{ id: 'one', text: 'SYNTHETIC suggestion only' }],
  },
});
const create = () =>
  mount(RecordingAnalysis, { props: { accountId: '1', recordingId: '15' } });
beforeEach(() => {
  api.qualityReview.mockReset();
  api.qualityReview.mockResolvedValue({ data: body() });
});

describe('authorized original analysis in the existing recording popup', () => {
  it('uses only the existing read endpoint and separates actual sentiment from quality zero and absent model/confidence', async () => {
    const wrapper = create();
    await flushPromises();
    expect(api.qualityReview).toHaveBeenCalledTimes(1);
    expect(api.qualityReview).toHaveBeenCalledWith('1', '15');
    expect(wrapper.get('[data-analysis-original-sentiment]').text()).toBe(
      'positivo'
    );
    expect(wrapper.get('[data-analysis-original-score]').text()).toBe('0');
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.QUALITY_REVIEW.UNKNOWN'
    );
    expect(wrapper.find('input, textarea, form').exists()).toBe(false);
  });

  it('renders source text, themes and recommendations safely as read-only suggestions', async () => {
    const wrapper = create();
    await flushPromises();
    expect(wrapper.get('[data-analysis-original-summary]').text()).toContain(
      '<img src=x onerror=alert(1)>'
    );
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.text()).toContain('SYNTHETIC theme');
    expect(wrapper.text()).toContain('SYNTHETIC suggestion only');
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('keeps the persisted human summary distinct from the immutable original', async () => {
    const data = body();
    data.latest_review = {
      revision: 3,
      source_sha256: data.source_sha256,
      values: { adjusted_summary: 'SYNTHETIC human summary' },
    };
    api.qualityReview.mockResolvedValue({ data });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.get('[data-analysis-latest-human]').text()).toContain(
      'SYNTHETIC human summary'
    );
    expect(wrapper.get('[data-analysis-original-summary]').text()).toContain(
      'SYNTHETIC original'
    );
    expect(wrapper.find('[data-analysis-older-human-source]').exists()).toBe(
      false
    );
  });

  it('identifies a human correction of an older original source without presenting it as the current inference', async () => {
    const data = body();
    data.latest_review = {
      revision: 2,
      source_sha256: 'b'.repeat(64),
      values: { adjusted_summary: 'SYNTHETIC historical human summary' },
    };
    api.qualityReview.mockResolvedValue({ data });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.get('[data-analysis-older-human-source]').text()).toContain(
      'OLDER_SOURCE_REVIEW'
    );
    expect(wrapper.get('[data-analysis-original-summary]').text()).toContain(
      'SYNTHETIC original'
    );
  });

  it('does not turn an unavailable source into zero, empty sentiment or editable content and supports an explicit read retry', async () => {
    api.qualityReview.mockRejectedValueOnce({ response: { status: 503 } });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'SOURCE_UNAVAILABLE'
    );
    expect(wrapper.find('[data-analysis-original-score]').exists()).toBe(false);
    await wrapper.get('[data-recording-analysis-retry]').trigger('click');
    await flushPromises();
    expect(api.qualityReview).toHaveBeenCalledTimes(2);
    expect(wrapper.get('[data-analysis-original-score]').text()).toBe('0');
  });

  it('rejects a response with a different account or recording before showing any original text', async () => {
    api.qualityReview.mockResolvedValue({
      data: { ...body(), account_id: '2' },
    });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('ERROR');
    expect(wrapper.text()).not.toContain('SYNTHETIC original');
  });

  it('clears the previous source immediately when the selected identity changes and respects the actual native denial', async () => {
    const wrapper = create();
    await flushPromises();
    api.qualityReview.mockRejectedValueOnce({ response: { status: 403 } });
    await wrapper.setProps({ recordingId: '16' });
    expect(wrapper.find('[data-analysis-original-summary]').exists()).toBe(
      false
    );
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('DENIED');
    expect(api.qualityReview).toHaveBeenLastCalledWith('1', '16');
  });

  it('ignores a late previous-account response after the new account read is denied', async () => {
    let finish;
    api.qualityReview.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = create();
    api.qualityReview.mockRejectedValueOnce({ response: { status: 401 } });
    await wrapper.setProps({ accountId: '2' });
    await flushPromises();
    finish({ data: body() });
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('DENIED');
    expect(wrapper.text()).not.toContain('SYNTHETIC original');
  });

  it('presents the explicit native alert independently of positive sentiment and escapes its source reason', async () => {
    const data = body();
    data.original.alerta_supervisao = true;
    data.original.motivo_alerta = 'SYNTHETIC <script>source reason</script>';
    api.qualityReview.mockResolvedValue({ data });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.get('[data-analysis-supervision-state]').text()).toContain(
      'SUPERVISION_PRESENT'
    );
    expect(wrapper.get('[data-analysis-supervision-reason]').text()).toContain(
      data.original.motivo_alerta
    );
    expect(wrapper.get('[data-analysis-original-sentiment]').text()).toBe(
      'positivo'
    );
    expect(wrapper.find('script, form, input').exists()).toBe(false);
    expect(wrapper.get('[data-analysis-original-score]').text()).toBe('0');
  });

  it('preserves an actual false flag when the original sentiment is negative without inferring criticality', async () => {
    const data = body();
    Object.assign(data.original, {
      sentimento_cliente: 'negativo',
      alerta_supervisao: false,
    });
    api.qualityReview.mockResolvedValue({ data });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.get('[data-analysis-supervision-state]').text()).toContain(
      'SUPERVISION_ABSENT'
    );
    expect(wrapper.get('[data-analysis-original-sentiment]').text()).toBe(
      'negativo'
    );
    expect(wrapper.find('[data-analysis-supervision-reason]').exists()).toBe(
      false
    );
  });

  it('does not treat an absent or malformed flag as false or use JavaScript truthiness', async () => {
    const wrappers = [undefined, null, 'false', 0].map(value => {
      const data = body();
      data.original.alerta_supervisao = value;
      api.qualityReview.mockResolvedValueOnce({ data });
      return create();
    });
    await flushPromises();
    wrappers.forEach(wrapper => {
      expect(wrapper.get('[data-analysis-supervision-state]').text()).toContain(
        'UNKNOWN'
      );
      expect(wrapper.find('button').exists()).toBe(false);
      wrapper.unmount();
    });
  });

  it('does not replace the source alert with a human sentiment revision', async () => {
    const data = body();
    data.original.alerta_supervisao = false;
    data.latest_review = {
      revision: 1,
      source_sha256: data.source_sha256,
      values: {
        classification: 'negative',
        adjusted_summary: 'SYNTHETIC revised summary',
      },
    };
    api.qualityReview.mockResolvedValue({ data });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.get('[data-analysis-latest-human]').text()).toContain(
      'SYNTHETIC revised summary'
    );
    expect(wrapper.get('[data-analysis-supervision-state]').text()).toContain(
      'SUPERVISION_ABSENT'
    );
    expect(wrapper.get('[data-analysis-original-sentiment]').text()).toBe(
      'positivo'
    );
  });
});
