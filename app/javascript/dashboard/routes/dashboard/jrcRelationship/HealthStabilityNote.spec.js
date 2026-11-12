import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import messages from 'dashboard/i18n/locale/en/relationship.json';
import HealthStabilityNote from './HealthStabilityNote.vue';

describe('health recovery margin explanation', () => {
  it('explains a retained band without replacing the measured score', () => {
    const health = {
      score: 41,
      band: 'critical',
      raw_band: 'risk',
      hysteresis: { points: 5, retained: true },
    };
    const wrapper = mount(HealthStabilityNote, {
      props: { health },
    });
    expect(wrapper.text()).toContain('5-point recovery margin');
    expect(wrapper.text()).toContain(messages.RELATIONSHIP.BANDS.risk);
    expect(health.score).toBe(41);
    wrapper.unmount();
  });
  it.each([
    {},
    { score: null },
    { score: 70, hysteresis: { retained: false } },
  ])('does not invent a stability warning for %s', health => {
    const wrapper = mount(HealthStabilityNote, {
      props: { health },
    });
    expect(wrapper.find('[data-testid="health-stability-note"]').exists()).toBe(
      false
    );
    wrapper.unmount();
  });
});
