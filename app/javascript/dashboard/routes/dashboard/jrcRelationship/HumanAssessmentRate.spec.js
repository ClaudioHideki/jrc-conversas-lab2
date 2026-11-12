import { mount } from '@vue/test-utils';
import { expect, it } from 'vitest';
import Rate from './HumanAssessmentRate.vue';

it('shows the human-reviewed numerator and denominator with the account number format', () => {
  const wrapper = mount(Rate, {
    props: {
      summary: { confirmed: 2, reviewed: 3, human_confirmation_percent: 66.7 },
      formatting: { locale: 'pt-BR' },
    },
  });
  expect(wrapper.text()).toContain('66,7% (2/3)');
  expect(wrapper.text()).toContain('not model precision');
  expect(wrapper.text()).not.toContain('RELATIONSHIP.');
  wrapper.unmount();
});

it('keeps an actual zero confirmation rate visible', () => {
  const wrapper = mount(Rate, {
    props: {
      summary: { confirmed: 0, reviewed: 1, human_confirmation_percent: 0 },
    },
  });
  expect(wrapper.text()).toContain('0% (0/1)');
  expect(wrapper.text()).not.toContain('unavailable');
  wrapper.unmount();
});

it('shows unavailable instead of a fabricated zero when no current assessments exist', () => {
  const wrapper = mount(Rate, {
    props: {
      summary: { confirmed: 0, reviewed: 0, human_confirmation_percent: null },
    },
  });
  expect(wrapper.text()).toContain('rate is unavailable');
  expect(wrapper.text()).not.toContain('0%');
  wrapper.unmount();
});

it('keeps older count-only responses usable without inventing a percentage', () => {
  const wrapper = mount(Rate, {
    props: { summary: { confirmed: 2, false_positive: 1 } },
  });
  expect(wrapper.text()).toContain('rate is unavailable');
  expect(wrapper.text()).not.toContain('NaN');
  wrapper.unmount();
});

it('updates when a former assessment becomes stale', async () => {
  const wrapper = mount(Rate, {
    props: {
      summary: { confirmed: 1, reviewed: 1, human_confirmation_percent: 100 },
    },
  });
  expect(wrapper.text()).toContain('100% (1/1)');
  await wrapper.setProps({
    summary: { confirmed: 0, reviewed: 0, human_confirmation_percent: null },
  });
  expect(wrapper.text()).toContain('rate is unavailable');
  expect(wrapper.text()).not.toContain('100%');
  wrapper.unmount();
});
