import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import MetricsPanel from './MetricsPanel.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => `${key}${values ? ` ${JSON.stringify(values)}` : ''}`,
  }),
}));
const evidence = {
  customer_key: 'company:31',
  assignment_ids: [7, 8],
  snapshot_ids: [91, 92],
  contract_ids: [51],
  observed_at: '2026-10-02T16:00:00Z',
  mrr_cents: 100000,
  reason: null,
};
const panel = evolution =>
  mount(MetricsPanel, {
    props: {
      mode: 'all',
      metrics: { mrr_evolution: evolution },
      metadata: { formatting: { locale: 'en-US', currency: 'BRL' } },
    },
  });

describe('Observed recurring MRR evolution', () => {
  it('renders only actual days with exact coverage and source evidence, preserving observed zero', () => {
    const wrapper = panel({
      basis: 'observed_recurring_snapshots',
      timezone: 'America/Sao_Paulo',
      period: { from: '2026-10-01', to: '2026-10-08' },
      points: [
        {
          day: '2026-10-02',
          observed_mrr_cents: 100000,
          mrr_cents: null,
          coverage: {
            eligible: 2,
            observed: 1,
            covered: 1,
            missing: 1,
            unknown: 0,
            complete: false,
          },
          evidence: [evidence],
        },
        {
          day: '2026-10-04',
          observed_mrr_cents: 0,
          mrr_cents: 0,
          coverage: {
            eligible: 2,
            observed: 2,
            covered: 2,
            missing: 0,
            unknown: 0,
            complete: true,
          },
          evidence: [
            { ...evidence, snapshot_ids: [93], mrr_cents: 0, contract_ids: [] },
          ],
        },
      ],
    });
    const rows = wrapper.findAll(
      '[data-testid="relationship-mrr-observation"]'
    );
    expect(rows).toHaveLength(2);
    expect(rows[0].text()).toContain('2026-10-02');
    expect(rows[0].text()).toContain('RELATIONSHIP.UNAVAILABLE');
    expect(rows[0].text()).toContain('1,000.00');
    expect(rows[0].text()).toContain('"missing":1');
    expect(rows[0].text()).toContain('91, 92');
    expect(rows[0].text()).toContain('7, 8');
    expect(rows[0].text()).toContain('51');
    expect(rows[1].text()).toContain('0.00');
    expect(rows[1].text()).not.toContain('RELATIONSHIP.UNAVAILABLE');
    expect(wrapper.text()).not.toContain('2026-10-03');
    expect(wrapper.emitted('inspect')).toBeUndefined();
  });

  it('discloses conflicting evidence and a source access failure without inventing an empty zero series', async () => {
    const wrapper = panel({
      points: [
        {
          day: '2026-10-02',
          observed_mrr_cents: null,
          mrr_cents: null,
          coverage: {
            eligible: 1,
            observed: 1,
            covered: 0,
            unknown: 1,
            missing: 0,
            complete: false,
          },
          evidence: [
            {
              ...evidence,
              mrr_cents: null,
              reason: 'conflicting_customer_observations',
            },
          ],
        },
      ],
    });
    expect(wrapper.text()).toContain('RELATIONSHIP.MRR_EVIDENCE_CONFLICT');
    expect(wrapper.text()).toContain('"unknown":1');
    await wrapper.setProps({
      metrics: {
        mrr_evolution: { points: [], reason: 'financial_access_unavailable' },
      },
    });
    expect(wrapper.text()).toContain(
      'RELATIONSHIP.MRR_EVOLUTION_FINANCIAL_ACCESS'
    );
    expect(
      wrapper.findAll('[data-testid="relationship-mrr-observation"]')
    ).toHaveLength(0);
    expect(
      wrapper.find('[data-testid="relationship-mrr-evolution"]').text()
    ).not.toContain('0.00');
  });
});
