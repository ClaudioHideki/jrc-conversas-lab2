import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import QualityReviewDialog from './QualityReviewDialog.vue';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { qualityReview: vi.fn(), saveQualityReview: vi.fn() },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
enableAutoUnmount(afterEach);
const Dialog = defineComponent({
  emits: ['close'],
  setup(_, { slots, expose, emit }) {
    expose({ open: vi.fn(), close: () => emit('close') });
    return () => h('section', slots.default?.());
  },
});
const recording = {
  id: '15',
  unique_id: 'SYNTHETIC call',
  unit_name: 'SYNTHETIC unit',
  queue_name: 'SYNTHETIC queue',
};
const response = () => ({
  account_id: '1',
  recording_id: '15',
  revision: 0,
  source_sha256: 'a'.repeat(64),
  timezone: 'America/Sao_Paulo',
  can_review: true,
  latest_review: null,
  original: {
    sentimento_cliente: 'positivo',
    classificacao_ligacao: 'excelente',
    nota_final: 0,
    sentiment_confidence: null,
    confianca_transcricao: 0.88,
    model: null,
    resumo_conversa: 'SYNTHETIC immutable original',
    themes: ['SYNTHETIC service'],
    recommendations: [{ id: 'b'.repeat(64), text: 'SYNTHETIC suggestion' }],
  },
});
const create = () =>
  mount(QualityReviewDialog, {
    props: { accountId: '1', recording },
    global: { stubs: { Dialog } },
  });
const fill = async wrapper => {
  await wrapper.get('input[value="negative"]').setValue(true);
  await wrapper
    .get('[data-quality-summary]')
    .setValue('SYNTHETIC reviewed text');
  await wrapper
    .get('[data-quality-justification]')
    .setValue('SYNTHETIC explicit justification');
};
beforeEach(() => {
  API.qualityReview.mockReset().mockResolvedValue({ data: response() });
  API.saveQualityReview.mockReset().mockResolvedValue({
    data: {
      account_id: '1',
      recording_id: '15',
      item: { id: '7', revision: 1 },
    },
  });
});

describe('native recording human quality review dialog', () => {
  it('shows absent native analysis as unavailable instead of manufacturing a score, sentiment or editable source', async () => {
    API.qualityReview.mockRejectedValue({
      response: {
        status: 422,
        data: { error: 'quality_analysis_source_unavailable' },
      },
    });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'SOURCE_UNAVAILABLE'
    );
    expect(wrapper.find('[data-quality-original-score]').exists()).toBe(false);
    expect(wrapper.find('[data-quality-save]').exists()).toBe(false);
    expect(wrapper.emitted('close')).toBeUndefined();
    expect(API.saveQualityReview).not.toHaveBeenCalled();
  });
  it('does not carry an unresolved save, source or success event into a newly selected authorized account', async () => {
    let resolve;
    API.saveQualityReview.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = create();
    await flushPromises();
    await fill(wrapper);
    await wrapper.get('[data-quality-save]').trigger('click');
    API.qualityReview.mockResolvedValueOnce({
      data: { ...response(), account_id: '2', recording_id: '16' },
    });
    await wrapper.setProps({
      accountId: '2',
      recording: { ...recording, id: '16' },
    });
    await flushPromises();
    expect(wrapper.get('[data-quality-justification]').element.disabled).toBe(
      false
    );
    expect(wrapper.get('[data-quality-justification]').element.value).toBe('');
    resolve({
      data: { account_id: '1', recording_id: '15', item: { id: '7' } },
    });
    await flushPromises();
    expect(wrapper.emitted('saved')).toBeUndefined();
    expect(wrapper.emitted('close')).toBeUndefined();
  });
  it('requires explicit reconciliation when a fresh source no longer contains previously selected suggestions', async () => {
    API.saveQualityReview.mockRejectedValueOnce({ response: { status: 409 } });
    const wrapper = create();
    await flushPromises();
    await fill(wrapper);
    await wrapper.get('[data-quality-save]').trigger('click');
    await flushPromises();
    const current = response();
    current.source_sha256 = 'c'.repeat(64);
    current.original.recommendations = [];
    API.qualityReview.mockResolvedValueOnce({ data: current });
    await wrapper.get('[data-quality-conflict-review] button').trigger('click');
    await flushPromises();
    await wrapper
      .findAll('[data-quality-conflict-review] button')[1]
      .trigger('click');
    expect(wrapper.get('[data-quality-save]').element.disabled).toBe(true);
    expect(wrapper.get('[data-quality-summary]').element.value).toBe(
      'SYNTHETIC reviewed text'
    );
    await wrapper
      .get('[data-quality-unavailable-suggestions] button')
      .trigger('click');
    expect(wrapper.get('[data-quality-save]').element.disabled).toBe(false);
    await wrapper.get('[data-quality-save]').trigger('click');
    await flushPromises();
    expect(API.saveQualityReview.mock.calls[1][2].recommendation_ids).toEqual(
      []
    );
  });
  it('keeps sentiment, quality score zero, missing confidence/model and original text separate without a default human classification', async () => {
    const wrapper = create();
    await flushPromises();
    expect(wrapper.get('[data-quality-original-summary]').text()).toBe(
      'SYNTHETIC immutable original'
    );
    expect(wrapper.text()).toContain('excelente');
    expect(wrapper.text()).toContain('0.88');
    expect(wrapper.get('[data-quality-original-score]').text()).toBe('0');
    expect(
      wrapper
        .findAll('input[type="radio"]')
        .every(input => !input.element.checked)
    ).toBe(true);
    expect(wrapper.get('[data-quality-save]').element.disabled).toBe(true);
    expect(API.saveQualityReview).not.toHaveBeenCalled();
  });

  it('requires explicit classification and justification and sends only the native review envelope values', async () => {
    const wrapper = create();
    await flushPromises();
    expect(wrapper.get('[data-quality-required]').text()).toContain(
      'CLASS_REQUIRED'
    );
    await wrapper.get('input[value="negative"]').setValue();
    expect(wrapper.get('[data-quality-required]').text()).toContain(
      'REASON_REQUIRED'
    );
    expect(wrapper.get('[data-quality-save]').element.disabled).toBe(true);
    expect(API.saveQualityReview).not.toHaveBeenCalled();
    await fill(wrapper);
    expect(wrapper.find('[data-quality-required]').exists()).toBe(false);
    await wrapper.get('[data-quality-save]').trigger('click');
    await flushPromises();
    expect(API.saveQualityReview).toHaveBeenCalledTimes(1);
    expect(API.saveQualityReview).toHaveBeenCalledWith(
      '1',
      '15',
      expect.objectContaining({
        classification: 'negative',
        justification: 'SYNTHETIC explicit justification',
        expected_revision: 0,
        expected_source_sha256: 'a'.repeat(64),
        recommendation_ids: ['b'.repeat(64)],
      })
    );
    const input = API.saveQualityReview.mock.calls[0][2];
    expect(Object.keys(input).sort()).toEqual(
      [
        'adjusted_summary',
        'adjusted_themes',
        'classification',
        'expected_revision',
        'expected_source_sha256',
        'justification',
        'recommendation_ids',
        'request_id',
      ].sort()
    );
    expect(wrapper.emitted('saved')).toHaveLength(1);
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('preserves the draft on failed persistence and retries the unchanged intent with the same request ID', async () => {
    API.saveQualityReview.mockRejectedValueOnce({ response: { status: 500 } });
    const wrapper = create();
    await flushPromises();
    await fill(wrapper);
    await wrapper.get('[data-quality-save]').trigger('click');
    await flushPromises();
    expect(wrapper.emitted('close')).toBeUndefined();
    expect(wrapper.get('[data-quality-summary]').element.value).toBe(
      'SYNTHETIC reviewed text'
    );
    await wrapper.get('[data-quality-save]').trigger('click');
    await flushPromises();
    expect(API.saveQualityReview.mock.calls[1][2].request_id).toBe(
      API.saveQualityReview.mock.calls[0][2].request_id
    );
  });

  it('blocks stale resubmission, loads the actual new source without overwriting the draft and requires explicit reviewed reapplication', async () => {
    API.saveQualityReview.mockRejectedValueOnce({ response: { status: 409 } });
    const wrapper = create();
    await flushPromises();
    await fill(wrapper);
    await wrapper.get('[data-quality-save]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-quality-save]').element.disabled).toBe(true);
    API.qualityReview.mockResolvedValueOnce({
      data: { ...response(), revision: 1, source_sha256: 'c'.repeat(64) },
    });
    await wrapper.get('[data-quality-conflict-review] button').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-quality-summary]').element.value).toBe(
      'SYNTHETIC reviewed text'
    );
    expect(wrapper.get('[data-quality-save]').element.disabled).toBe(true);
    await wrapper
      .findAll('[data-quality-conflict-review] button')[1]
      .trigger('click');
    await wrapper.get('[data-quality-save]').trigger('click');
    await flushPromises();
    expect(API.saveQualityReview.mock.calls[1][2]).toMatchObject({
      expected_revision: 1,
      expected_source_sha256: 'c'.repeat(64),
    });
    expect(API.saveQualityReview.mock.calls[1][2].request_id).not.toBe(
      API.saveQualityReview.mock.calls[0][2].request_id
    );
  });

  it('never presents an editable correction merely because a caller can read the source', async () => {
    API.qualityReview.mockResolvedValue({
      data: { ...response(), can_review: false },
    });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.get('[data-quality-original-summary]').text()).toContain(
      'immutable original'
    );
    expect(wrapper.find('[data-quality-save]').exists()).toBe(false);
    expect(wrapper.find('[data-quality-justification]').exists()).toBe(false);
    expect(wrapper.find('[data-quality-classification]').exists()).toBe(false);
  });

  it('purges visible source and editing controls on an actual denied save instead of accepting cached authority', async () => {
    API.saveQualityReview.mockRejectedValue({ response: { status: 401 } });
    const wrapper = create();
    await flushPromises();
    await fill(wrapper);
    await wrapper.get('[data-quality-save]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-quality-original-summary]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-quality-summary]').exists()).toBe(false);
    expect(wrapper.get('[role="alert"]').text()).toContain('DENIED');
  });

  it('prevents duplicate submissions while a native write is still unresolved', async () => {
    let resolve;
    API.saveQualityReview.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = create();
    await flushPromises();
    await fill(wrapper);
    await wrapper.get('[data-quality-save]').trigger('click');
    await wrapper.get('[data-quality-save]').trigger('click');
    expect(API.saveQualityReview).toHaveBeenCalledTimes(1);
    resolve({
      data: { account_id: '1', recording_id: '15', item: { id: '7' } },
    });
    await flushPromises();
  });

  it('ignores a late response from another account or recording after the selected source changes', async () => {
    let resolve;
    API.qualityReview.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = create();
    await wrapper.setProps({
      accountId: '2',
      recording: { ...recording, id: '16' },
    });
    await flushPromises();
    resolve({ data: response() });
    await flushPromises();
    expect(wrapper.find('[data-quality-original-summary]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-quality-save]').exists()).toBe(false);
  });

  it('requires explicit discard after an unsaved summary change, even before classification or reason is selected', async () => {
    const wrapper = create();
    await flushPromises();
    await wrapper
      .get('[data-quality-summary]')
      .setValue('SYNTHETIC unsaved change');
    const cancel = wrapper
      .findAll('button')
      .find(button => button.text().endsWith('.CANCEL'));
    await cancel.trigger('click');
    expect(wrapper.emitted('close')).toBeUndefined();
    expect(wrapper.get('[data-quality-discard]').exists()).toBe(true);
    await wrapper.findAll('[data-quality-discard] button')[1].trigger('click');
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(API.saveQualityReview).not.toHaveBeenCalled();
  });

  it('shows the scoped persisted human correction to a read-only listener without replacing the current original', async () => {
    API.qualityReview.mockResolvedValue({
      data: {
        ...response(),
        can_review: false,
        revision: 2,
        latest_review: {
          revision: 2,
          actor_id: '4',
          created_at: '2026-11-26T12:00:00Z',
          source_sha256: 'a'.repeat(64),
          values: {
            classification: 'negative',
            adjusted_summary: 'SYNTHETIC human summary',
            adjusted_themes: [],
            justification: 'SYNTHETIC reason',
          },
        },
      },
    });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.get('[data-quality-current-human-review]').text()).toContain(
      'SYNTHETIC human summary'
    );
    expect(wrapper.get('[data-quality-original-summary]').text()).toContain(
      'SYNTHETIC immutable original'
    );
    expect(wrapper.find('[data-quality-save]').exists()).toBe(false);
  });
});
