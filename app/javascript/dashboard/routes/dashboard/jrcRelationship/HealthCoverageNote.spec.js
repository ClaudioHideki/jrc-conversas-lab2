import { mount } from '@vue/test-utils';
import { expect, it } from 'vitest';
import Note from './HealthCoverageNote.vue';

it('shows the observed weight independently from an imputed calculation weight', () => {
  const wrapper = mount(Note, {
    props: {
      health: {
        score: 82,
        coverage_weight: 40,
        calculation_weight: 100,
        missing_factor_policy: 'neutral',
      },
    },
  });
  const rows = wrapper.findAll('p').map(row => row.text());
  expect(rows[0]).toContain('coverage: 40%');
  expect(rows[1]).toContain('calculation: 100%');
  expect(wrapper.text()).toContain('neutral value');
  expect(wrapper.text()).toContain('not the health score or model confidence');
  expect(wrapper.text()).not.toContain('RELATIONSHIP.');
  wrapper.unmount();
});

it('keeps genuine zero observed coverage visible when all factors are missing', () => {
  const wrapper = mount(Note, {
    props: {
      health: { score: null, coverage_weight: 0, calculation_weight: 0 },
    },
  });
  expect(wrapper.findAll('p')[0].text()).toContain('coverage: 0%');
  expect(wrapper.text()).toContain('not a zero measurement');
  wrapper.unmount();
});

it('does not fabricate weights or the current default policy for legacy evidence', () => {
  const wrapper = mount(Note, { props: { health: { score: 90 } } });
  expect(wrapper.text()).not.toContain('90%');
  expect(wrapper.text()).not.toContain('100%');
  expect(wrapper.text()).not.toContain('policy:');
  wrapper.unmount();
});

it('formats the recorded renormalized denominator using the account locale', () => {
  const wrapper = mount(Note, {
    props: {
      health: {
        coverage_weight: 32.5,
        calculation_weight: 32.5,
        missing_factor_policy: 'renormalize',
      },
      formatting: { locale: 'pt-BR' },
    },
  });
  expect(wrapper.text()).toContain('32,5%');
  expect(wrapper.text()).toContain('Redistribute across available factors');
  wrapper.unmount();
});

it('drops unavailable coverage when navigating to a different historical observation', async () => {
  const wrapper = mount(Note, {
    props: {
      health: {
        coverage_weight: 100,
        calculation_weight: 100,
        missing_factor_policy: 'block',
      },
    },
  });
  expect(wrapper.text()).toContain('100%');
  await wrapper.setProps({ health: {} });
  expect(wrapper.text()).not.toContain('100%');
  expect(wrapper.text()).not.toContain('policy:');
  wrapper.unmount();
});
