import { afterEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import QualityReviewHistory from './QualityReviewHistory.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { qualityReviewHistory: vi.fn() },
}));
const row = (revision = 1) => ({
  id: String(revision),
  revision,
  source_sha256: 'a'.repeat(64),
  actor_id: '4',
  created_at: '2026-11-26T22:00:00Z',
  origin: 'human',
  original: {
    resumo_conversa: 'SYNTHETIC immutable original',
    sentimento_cliente: 'positivo',
    nota_final: 0,
    model: null,
  },
  values: {
    classification: 'negative',
    adjusted_summary: 'SYNTHETIC adjusted text',
    justification: 'SYNTHETIC human justification',
  },
});
const result = (page = 1, total = 1) => ({
  account_id: '1',
  recording_id: '15',
  timezone: 'America/Sao_Paulo',
  meta: { page, per_page: 20, total },
  items: Array.from(
    { length: Math.min(20, Math.max(0, total - (page - 1) * 20)) },
    (_, i) => row((page - 1) * 20 + i + 1)
  ),
});
const render = (props = {}) =>
  mount(QualityReviewHistory, {
    props: { accountId: '1', recordingId: '15', ...props },
  });
enableAutoUnmount(afterEach);
afterEach(() => vi.resetAllMocks());

describe('authorized immutable human revision history', () => {
  it('shows distinct original and human values, zero quality, actor and source timezone without offering writes', async () => {
    API.qualityReviewHistory.mockResolvedValue({ data: result() });
    const wrapper = render();
    await flushPromises();
    expect(API.qualityReviewHistory).toHaveBeenCalledWith('1', '15', {
      page: 1,
      per_page: 20,
    });
    expect(wrapper.get('[data-quality-history-original]').text()).toBe(
      'SYNTHETIC immutable original'
    );
    expect(wrapper.get('[data-quality-history-adjusted]').text()).toBe(
      'SYNTHETIC adjusted text'
    );
    expect(wrapper.text()).toContain('19:00');
    expect(wrapper.get('[data-quality-history-quality]').text()).toMatch(/0$/);
    expect(wrapper.text()).toContain('AUTHOR 4');
    expect(
      wrapper.get('[data-quality-history-source-version]').text()
    ).toContain('a'.repeat(64));
    expect(wrapper.find('form').exists()).toBe(false);
  });

  it('escapes the stored summaries and keeps absent original fields honest', async () => {
    const data = result();
    data.items[0].original.resumo_conversa = null;
    data.items[0].values.adjusted_summary =
      '<script>SYNTHETIC text only</script>';
    API.qualityReviewHistory.mockResolvedValue({ data });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[data-quality-history-original]').text()).toContain(
      'UNKNOWN'
    );
    expect(wrapper.get('[data-quality-history-adjusted]').text()).toBe(
      data.items[0].values.adjusted_summary
    );
    expect(wrapper.find('script').exists()).toBe(false);
  });

  it('paginates only through the existing scoped API and never retains the previous page as the next result', async () => {
    API.qualityReviewHistory.mockResolvedValueOnce({ data: result(1, 21) });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.findAll('[data-quality-history-revision]')).toHaveLength(20);
    API.qualityReviewHistory.mockResolvedValueOnce({ data: result(2, 21) });
    await wrapper.get('[data-quality-history-next]').trigger('click');
    await flushPromises();
    expect(API.qualityReviewHistory).toHaveBeenLastCalledWith('1', '15', {
      page: 2,
      per_page: 20,
    });
    expect(wrapper.findAll('[data-quality-history-revision]')).toHaveLength(1);
    expect(
      wrapper
        .get('[data-quality-history-revision]')
        .attributes('data-quality-history-revision')
    ).toBe('21');
    expect(wrapper.get('[data-quality-history-next]').element.disabled).toBe(
      true
    );
    expect(
      wrapper.get('[data-quality-history-previous]').element.disabled
    ).toBe(false);
  });

  it.each(['account_id', 'recording_id'])(
    'rejects a response from another %s',
    async field => {
      const data = result();
      data[field] = '99';
      API.qualityReviewHistory.mockResolvedValue({ data });
      const wrapper = render();
      await flushPromises();
      expect(wrapper.get('[role="alert"]').text()).toContain('ERROR');
      expect(wrapper.text()).not.toContain('SYNTHETIC human justification');
    }
  );

  it('ignores an old account response after a context switch and clears the previous rows before rendering', async () => {
    let first;
    API.qualityReviewHistory.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          first = resolve;
        })
    );
    API.qualityReviewHistory.mockRejectedValueOnce({
      response: { status: 403 },
    });
    const wrapper = render();
    await wrapper.setProps({ accountId: '2', recordingId: '16' });
    await flushPromises();
    first({ data: result() });
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('DENIED');
    expect(wrapper.text()).not.toContain('SYNTHETIC human justification');
    expect(API.qualityReviewHistory).toHaveBeenLastCalledWith('2', '16', {
      page: 1,
      per_page: 20,
    });
  });

  it('distinguishes an actual authorized empty list from a denied or unavailable history and supports explicit retry', async () => {
    API.qualityReviewHistory.mockRejectedValueOnce({
      response: { status: 401 },
    });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.find('[data-quality-history-empty]').exists()).toBe(false);
    expect(wrapper.get('[role="alert"]').text()).toContain('DENIED');
    API.qualityReviewHistory.mockResolvedValueOnce({ data: result(1, 0) });
    await wrapper.get('[data-quality-history-retry]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-quality-history-empty]').text()).toContain(
      'EMPTY'
    );
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it.each(['duplicates', 'timezone', 'missing-row'])(
    'rejects malformed %s without presenting zero data as a success',
    async kind => {
      const data = result(1, kind === 'duplicates' ? 2 : 1);
      if (kind === 'duplicates') data.items[1].id = data.items[0].id;
      if (kind === 'timezone') data.timezone = 'SYNTHETIC invalid zone';
      if (kind === 'missing-row') data.items = [];
      API.qualityReviewHistory.mockResolvedValue({ data });
      const wrapper = render();
      await flushPromises();
      expect(wrapper.get('[role="alert"]').text()).toContain('ERROR');
      expect(wrapper.find('[data-quality-history-empty]').exists()).toBe(false);
      expect(wrapper.text()).not.toContain('SYNTHETIC human justification');
    }
  );
});
