import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/en/jrcCampaigns.json';
import CampaignReport from '../components/CampaignReport.vue';
import api from 'dashboard/api/jrcCampaigns';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: { report: vi.fn(), exportUrl: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
enableAutoUnmount(afterEach);
const result = status => ({
  summary: {
    total: 1,
    sent: 1,
    delivered: 1,
    read: status === 'read' ? 1 : 0,
    replied: 0,
    failed: 0,
  },
  recipients: [{ id: 1, name: 'Synthetic', status }],
  pagination: { page: 1, pages: 2 },
});
const render = () =>
  mount(CampaignReport, {
    props: { campaign: { id: 7, name: 'QA' } },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
    },
  });

describe('campaign report receipt updates', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    api.report.mockResolvedValue({ data: result('delivered') });
  });
  afterEach(() => vi.useRealTimers());

  it('translates receipts and refreshes the current page until unmounted', async () => {
    const wrapper = render();
    await flushPromises();
    expect(wrapper.text()).toContain('Entregue');
    expect(wrapper.text()).not.toContain('delivered');
    await wrapper.vm.load(2);
    api.report.mockResolvedValue({ data: result('read') });
    await vi.advanceTimersByTimeAsync(15000);
    await flushPromises();
    expect(api.report).toHaveBeenLastCalledWith(7, { page: 2, per_page: 50 });
    expect(wrapper.text()).toContain('Lida');
    const calls = api.report.mock.calls.length;
    wrapper.unmount();
    await vi.advanceTimersByTimeAsync(30000);
    expect(api.report).toHaveBeenCalledTimes(calls);
  });

  it.each([
    ['131049', 'Unchanged provider text', 'A Meta restringiu'],
    [
      '131026',
      'This message was not delivered to maintain healthy ecosystem engagement.',
      'Não foi possível entregar',
    ],
    [
      null,
      'This message was not delivered to maintain healthy ecosystem engagement.',
      'A Meta restringiu',
    ],
    [null, 'Message undeliverable', 'Não foi possível entregar'],
    ['999999', 'Message undeliverable', 'O envio apresentou uma falha'],
  ])(
    'translates error code %s while preserving original technical evidence',
    async (code, original, expected) => {
      const data = result('failed');
      data.recipients[0].error_code = code;
      data.recipients[0].error_message = original;
      api.report.mockResolvedValue({ data });
      const wrapper = render();
      await flushPromises();
      const cell = wrapper.get('tbody td:last-child');
      expect(cell.get('p').text()).toContain(expected);
      const details = cell.get('details');
      expect(details.attributes('open')).toBeUndefined();
      expect(details.get('p').text()).toBe(original);
      if (code) expect(cell.text()).toContain(`Código do provedor: ${code}`);
    }
  );

  it('keeps the confirmed state on refresh failure and allows manual retry', async () => {
    const wrapper = render();
    await flushPromises();
    api.report.mockRejectedValueOnce(new Error('offline'));
    await wrapper.vm.load(1);
    expect(wrapper.text()).toContain('Entregue');
    expect(wrapper.vm.refreshing).toBe(false);
    expect(useAlert).toHaveBeenCalledWith(
      'Não foi possível atualizar o relatório. Tente novamente.'
    );
    api.report.mockResolvedValue({ data: result('read') });
    await wrapper
      .findAll('button')
      .find(b => b.text() === 'Atualizar')
      .trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Lida');
  });
});
