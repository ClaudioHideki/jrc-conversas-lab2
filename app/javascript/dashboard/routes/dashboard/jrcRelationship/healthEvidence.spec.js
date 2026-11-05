import { mount } from '@vue/test-utils';
import { expect, it, vi } from 'vitest';
import Summary from './HealthEvidenceSummary.vue';
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => `${key}${params ? JSON.stringify(params) : ''}`,
  }),
}));

it('shows stale source evidence separately from a low score and shows an actual trend baseline', () => {
  const wrapper = mount(Summary, {
    props: {
      signals: {
        health: {
          score: null,
          factors: [
            {
              factor: 'satisfaction',
              measurement: {
                state: 'stale',
                window_days: 14,
                observed_at: '2026-09-01T12:00:00Z',
              },
            },
          ],
        },
        health_trend: {
          state: 'declined',
          delta: -9,
          window_days: 7,
          baseline_at: '2026-10-01T12:00:00Z',
        },
      },
    },
  });
  expect(wrapper.text()).toContain('STATES.stale');
  expect(wrapper.text()).toContain('STATES.declined');
  expect(wrapper.text()).toContain('"delta":-9');
  expect(wrapper.text()).toContain('HEALTH_EVIDENCE.ANSWERED');
  expect(wrapper.text()).toContain('HEALTH_EVIDENCE.BASELINE');
  wrapper.unmount();
});

it('does not invent zero changes or answer dates when observations are missing', () => {
  const wrapper = mount(Summary, {
    props: {
      signals: {
        health: {
          factors: [
            {
              factor: 'satisfaction',
              measurement: { state: 'missing', window_days: 90 },
            },
          ],
        },
        health_trend: { state: 'insufficient', window_days: 30 },
      },
    },
  });
  expect(wrapper.text()).toContain('STATES.missing');
  expect(wrapper.text()).toContain('STATES.insufficient');
  expect(wrapper.text()).not.toContain('HEALTH_EVIDENCE.CHANGE');
  expect(wrapper.text()).not.toContain('HEALTH_EVIDENCE.ANSWERED');
  wrapper.unmount();
});

it('clears previous evidence when the authorized parent projection is removed', async () => {
  const wrapper = mount(Summary, {
    props: {
      signals: {
        health_trend: { state: 'improved', delta: 12, window_days: 7 },
      },
    },
  });
  expect(wrapper.find('section').exists()).toBe(true);
  await wrapper.setProps({ signals: {} });
  expect(wrapper.find('section').exists()).toBe(false);
  wrapper.unmount();
});

it('uses server read-time freshness for cached scores and explains the need to recalculate', () => {
  const wrapper = mount(Summary, {
    props: {
      signals: {
        health: {
          factors: [
            {
              factor: 'satisfaction',
              measurement: { state: 'current', window_days: 14 },
            },
          ],
        },
        satisfaction_evidence: {
          state: 'stale',
          window_days: 14,
          recalculation_required: true,
        },
      },
    },
  });
  expect(wrapper.text()).toContain('STATES.stale');
  expect(wrapper.text()).not.toContain('STATES.current');
  expect(wrapper.text()).toContain('HEALTH_EVIDENCE.REFRESH_REQUIRED');
  wrapper.unmount();
});
