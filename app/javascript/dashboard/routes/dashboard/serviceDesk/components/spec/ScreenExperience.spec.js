import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { describe, it, expect } from 'vitest';
import locale from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import KpiCard from '../KpiCard.vue';
import Panel from '../ServiceDeskPanel.vue';
import HistoryEventCard from '../HistoryEventCard.vue';
import LifecycleVisualEditor from '../LifecycleVisualEditor.vue';
import ClockThresholdEditor from '../ClockThresholdEditor.vue';
import { validDraft } from '../../__tests__/screenExperienceCases.js';

const createOptions = props => ({
  props,
  global: {
    plugins: [
      createI18n({ legacy: false, locale: 'en', messages: { en: locale } }),
    ],
    stubs: {
      Icon: true,
      Button: {
        props: ['label', 'disabled'],
        template: '<button :disabled="disabled"><slot />{{ label }}</button>',
      },
      LookupSelect: {
        name: 'LookupSelect',
        props: ['modelValue', 'unitId', 'resource', 'label', 'disabled'],
        emits: ['update:modelValue', 'selected'],
        template: '<select :aria-label="label" :disabled="disabled" />',
      },
      StatusSetEditor: true,
    },
  },
});
const ticket = {
  id: '20',
  account_id: '1',
  unit_id: '10',
  status: { id: '30', name: 'Working' },
};
const event = {
  id: '90',
  event_type: 'status_changed',
  account_id: '1',
  unit_id: '10',
  ticket_id: '20',
  created_at: '2026-10-09T12:00:00Z',
  author: { name: 'Synthetic agent' },
  data: { status_id: '30' },
};

describe('Service Desk screen interaction contract', () => {
  it('keeps the native panel action slot and accepts the actions slot used by screens', () => {
    const current = mount(Panel, {
      ...createOptions({ title: 'Test' }),
      slots: { actions: '<button>Refresh</button>' },
    });
    const legacy = mount(Panel, {
      ...createOptions({ title: 'Test' }),
      slots: { action: '<button>Legacy</button>' },
    });
    expect(current.text()).toContain('Refresh');
    expect(legacy.text()).toContain('Legacy');
  });
  it('makes interactive KPI keyboard-native and never invents a missing count', async () => {
    const wrapper = mount(
      KpiCard,
      createOptions({ label: 'Open', interactive: true, value: null })
    );
    expect(wrapper.element.tagName).toBe('BUTTON');
    await wrapper.trigger('click');
    expect(wrapper.emitted('activate')).toHaveLength(1);
    expect(wrapper.find('strong').text()).not.toBe('0');
  });
  it('renders authorized names and hides technical data until expanded', () => {
    const wrapper = mount(HistoryEventCard, createOptions({ ticket, event }));
    expect(wrapper.text()).toContain('Working');
    expect(wrapper.find('details').attributes('open')).toBeUndefined();
  });
  it('does not render a history event belonging to another ticket', () => {
    const wrapper = mount(
      HistoryEventCard,
      createOptions({ ticket, event: { ...event, ticket_id: '99' } })
    );
    expect(wrapper.text()).not.toContain('Synthetic agent');
    expect(wrapper.find('details').exists()).toBe(false);
  });
  it('edits an explicit lifecycle draft without dropping advanced fields or publishing', async () => {
    const wrapper = mount(
      LifecycleVisualEditor,
      createOptions({ modelValue: validDraft(), unitId: '10' })
    );
    await wrapper.find('input[maxlength="80"]').setValue('resolve-reviewed');
    const updated = JSON.parse(wrapper.emitted('update:modelValue')[0][0]);
    expect(updated.transitions[0].key).toBe('resolve-reviewed');
    expect(updated.transitions[0].requirements.fields.reviewed.equals).toBe(
      true
    );
    expect(wrapper.emitted('publish')).toBeUndefined();
  });
  it('malformed advanced input cannot render unsafe visual rows or emit changes', () => {
    const wrapper = mount(
      LifecycleVisualEditor,
      createOptions({ modelValue: '{bad', unitId: '10' })
    );
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(wrapper.find('article').exists()).toBe(false);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });
  it('changing a threshold queue clears a stale team and turns automatic execution OFF', async () => {
    const wrapper = mount(
      ClockThresholdEditor,
      createOptions({
        unitId: '10',
        modelValue: {
          enabled: true,
          automatic: true,
          thresholds: [{ percent: 80, queue_id: '2', team_id: '5' }],
        },
      })
    );
    const selects = wrapper.findAllComponents({ name: 'LookupSelect' });
    const lookup = selects[0];
    expect(lookup).toBeDefined();
    lookup.vm.$emit('update:modelValue', '3');
    await wrapper.vm.$nextTick();
    const updated = wrapper.emitted('update:modelValue')[0][0];
    expect(updated.thresholds[0]).toEqual({
      percent: 80,
      queue_id: '3',
      team_id: null,
    });
    expect(updated.automatic).toBe(false);
  });
});
