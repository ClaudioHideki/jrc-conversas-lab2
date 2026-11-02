import { describe, expect, it } from 'vitest';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import pt from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import en from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import ObservedTimes from '../ObservedTimesPanel.vue';
describe('native observed wall time without an inferred SLA result', () => {
  it.each([
    ['pt_BR', '6.000,5'],
    ['en', '6,000.5'],
  ])('renders real facts with application locale %s', (locale, formatted) => {
    const wrapper = mount(ObservedTimes, {
      props: {
        measurement: {
          basis: 'elapsed_wall_time',
          result: 'unavailable',
          pending_reason: 'targets_missing',
          first_response: { elapsed_seconds: 0 },
          resolution: null,
          closure: { elapsed_seconds: 6000.5 },
        },
      },
      global: {
        plugins: [
          createI18n({ legacy: false, locale, messages: { pt_BR: pt, en } }),
        ],
      },
    });
    const values = wrapper.findAll('dd').map(row => row.text());
    expect(values[0]).toContain('0');
    expect(values[2]).toContain(formatted);
    expect(values[1]).toBe(
      (locale === 'pt_BR' ? pt : en).JRC_SERVICE_DESK.SIMPLE_SLA.no_event
    );
    expect(wrapper.text()).toContain(
      (locale === 'pt_BR' ? pt : en).JRC_SERVICE_DESK.SIMPLE_SLA
        .result_unavailable
    );
    wrapper.unmount();
  });
});
