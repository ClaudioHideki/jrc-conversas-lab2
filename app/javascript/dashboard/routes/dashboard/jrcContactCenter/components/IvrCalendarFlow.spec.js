import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import IvrFlowEditor from 'dashboard/routes/dashboard/jrcContactCenter/components/IvrFlowEditor.vue';
import IvrFlowOverview from 'dashboard/routes/dashboard/jrcContactCenter/components/IvrFlowOverview.vue';
import IvrCalendarReferencePicker from 'dashboard/routes/dashboard/jrcContactCenter/components/IvrCalendarReferencePicker.vue';
import IvrDraftEditor from 'dashboard/routes/dashboard/jrcContactCenter/components/IvrDraftEditor.vue';
import { newCalendarDefinition } from 'dashboard/routes/dashboard/jrcContactCenter/helpers/calendarForm';
import locale from 'dashboard/i18n/locale/en/jrcContactCenter.json';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    unitCalendars: vi.fn(),
    unitCalendar: vi.fn(),
    configurationRecord: vi.fn(),
    saveIvrDraft: vi.fn(),
    previewIvrDraft: vi.fn(),
  },
}));
const reference = () => {
  const definition = {
    ...newCalendarDefinition('America/Sao_Paulo'),
    name: 'SYNTHETIC fixed hours',
  };
  definition.weekly['1'] = [['08:00', '12:00']];
  const id = '11111111-1111-4111-8111-111111111111';
  return {
    calendar_id: id,
    sha256: 'b'.repeat(64),
    unit_revision: 'a'.repeat(64),
    snapshot: { id, active: false, definition },
  };
};
const graph = () => ({
  schema_version: 3,
  start: 'hours',
  nodes: [
    {
      id: 'hours',
      type: 'calendar',
      calendar_reference: reference(),
      on_open: 'opened',
      on_closed: 'closed',
    },
    { id: 'opened', type: 'end' },
    { id: 'closed', type: 'end' },
  ],
});
const saved = () => ({
  id: '10',
  unit_id: '7',
  name: 'SYNTHETIC saved URA',
  status: 'draft',
  revision: 1,
  definition: graph(),
});
const dialog = defineComponent({
  setup(props, { expose, slots }) {
    expose({ open: vi.fn(), close: vi.fn() });
    return () => h('div', [slots.default?.(), slots.footer?.()]);
  },
});
const mountEditor = () =>
  mount(IvrDraftEditor, {
    props: { accountId: '1', draftId: '10' },
    global: { stubs: { Dialog: dialog, IvrReferencePicker: true } },
  });
const preview = wrapper =>
  wrapper
    .findAll('button')
    .find(
      button => button.text() === locale.JRC_CONTACT_CENTER.LOCAL_IVR.SIMULATE
    );
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  API.configurationRecord.mockResolvedValue({
    data: { item: saved(), timezone: 'UTC' },
  });
  API.unitCalendars.mockResolvedValue({
    data: {
      account_id: '1',
      unit_id: '7',
      local_only: true,
      pabx_confirmed: false,
      revision: 'a'.repeat(64),
      items: [reference().snapshot],
      meta: { total: 1, page: 1, per_page: 20, pages: 1 },
    },
  });
  API.unitCalendar.mockResolvedValue({
    data: {
      account_id: '1',
      unit_id: '7',
      local_only: true,
      pabx_confirmed: false,
      revision: 'a'.repeat(64),
      item: reference().snapshot,
      ivr_reference: reference(),
    },
  });
  API.previewIvrDraft.mockResolvedValue({
    data: {
      simulation: {
        local_only: true,
        provider_applied: false,
        outcome: 'ended',
        trace: [
          {
            node_id: 'hours',
            type: 'calendar',
            event: 'calendar_open',
            calendar: {
              open: true,
              instant: '2026-11-23T13:00:00Z',
              timezone: 'America/Sao_Paulo',
              precedence: 'exception',
              snapshot_active: false,
            },
          },
          { node_id: 'opened', type: 'end' },
        ],
      },
    },
  });
});

describe('existing URA editor calendar controls with native components; not browser or server proof', () => {
  it('adds a calendar step through the existing flow editor without inventing a pin', async () => {
    const value = {
      schema_version: 1,
      start: 'done',
      nodes: [{ id: 'done', type: 'end' }],
    };
    const wrapper = mount(IvrFlowEditor, {
      props: { accountId: '1', unitId: '7', modelValue: value },
    });
    await wrapper.get('[data-ivr-add="calendar"]').trigger('click');
    const changed = wrapper.emitted('update:modelValue')[0][0];
    expect(changed.schema_version).toBe(3);
    expect(changed.nodes[1]).toMatchObject({
      type: 'calendar',
      calendar_reference: null,
      on_open: '',
      on_closed: '',
    });
    expect(value.nodes).toHaveLength(1);
  });

  it('names both branch controls and preserves the other destination when one is edited', async () => {
    const wrapper = mount(IvrFlowEditor, {
      props: { accountId: '1', unitId: '7', modelValue: graph() },
    });
    expect(wrapper.get('label[for="ivr-on_open-0"]').text()).toBe(
      'Destino no expediente aberto'
    );
    expect(wrapper.get('label[for="ivr-on_closed-0"]').text()).toBe(
      'Destino no expediente fechado'
    );
    await wrapper.get('#ivr-on_open-0').setValue('closed');
    expect(wrapper.emitted('update:modelValue')[0][0].nodes[0]).toMatchObject({
      on_open: 'closed',
      on_closed: 'closed',
    });
  });

  it('draws two actual edges instead of presenting the calendar as an ended call', () => {
    const wrapper = mount(IvrFlowOverview, { props: { modelValue: graph() } });
    const node = wrapper.get('[data-ivr-map-node="hours"]');
    expect(node.findAll('li').map(row => row.text())).toEqual([
      expect.stringContaining('Destino no expediente aberto'),
      expect.stringContaining('Destino no expediente fechado'),
    ]);
    expect(node.text()).toContain('opened');
    expect(node.text()).toContain('closed');
    expect(node.text()).not.toContain('Encerramento');
  });

  it('shows the inactive internal state in both the fixed snapshot and the review before consent', async () => {
    const wrapper = mount(IvrCalendarReferencePicker, {
      props: { accountId: '1', unitId: '7', modelValue: reference() },
    });
    expect(wrapper.get('[data-ivr-calendar-pinned]').text()).toContain(
      locale.JRC_CONTACT_CENTER.CALENDAR.INACTIVE_INTERNAL
    );
    await wrapper.get('[data-ivr-calendar-choose]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-ivr-calendar-select]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-ivr-calendar-candidate-state]').text()).toBe(
      locale.JRC_CONTACT_CENTER.CALENDAR.INACTIVE_INTERNAL
    );
    expect(
      wrapper.get('[data-ivr-calendar-use]').attributes('disabled')
    ).toBeDefined();
    await wrapper.get('[data-ivr-calendar-confirm]').setValue(true);
    await wrapper.get('[data-ivr-calendar-use]').trigger('click');
    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual(reference());
    expect(API.saveIvrDraft).not.toHaveBeenCalled();
  });

  it('uses an explicit local date/time, the chosen timezone and the saved origin, then invalidates an obsolete result', async () => {
    const wrapper = mountEditor();
    await flushPromises();
    expect(wrapper.get('#ivr-simulation-local').element.value).toBe('');
    expect(API.previewIvrDraft).not.toHaveBeenCalled();
    await wrapper.get('#ivr-simulation-local').setValue('2026-11-23T10:00');
    await preview(wrapper).trigger('click');
    await flushPromises();
    expect(API.previewIvrDraft).toHaveBeenCalledExactlyOnceWith('1', {
      unit_id: '7',
      definition: graph(),
      dtmf: '',
      origin_draft_id: '10',
      at: { local: '2026-11-23T10:00', timezone: 'America/Sao_Paulo' },
    });
    expect(wrapper.get('[data-ivr-calendar-decision]').text()).toContain(
      'Exceção explícita da data'
    );
    await wrapper.get('#ivr-simulation-local').setValue('2026-11-23T11:00');
    expect(wrapper.find('[data-ivr-simulation]').exists()).toBe(false);
  });

  it.each([1, 2])(
    'preserves the exact legacy schema%i preview wire contract without an added clock or origin',
    async schema => {
      const item = saved();
      item.definition = {
        schema_version: schema,
        start: 'done',
        nodes: [{ id: 'done', type: 'end' }],
      };
      API.configurationRecord.mockResolvedValueOnce({
        data: { item, timezone: 'UTC' },
      });
      const wrapper = mountEditor();
      await flushPromises();
      expect(wrapper.find('[data-ivr-calendar-instant]').exists()).toBe(false);
      await preview(wrapper).trigger('click');
      await flushPromises();
      expect(API.previewIvrDraft.mock.calls[0][1]).toEqual({
        unit_id: '7',
        definition: item.definition,
        dtmf: '',
      });
    }
  );

  it.each(['ivr_calendar_changed', 'ivr_calendar_attestation_conflict'])(
    'preserves the editable draft after definite native refusal %s rather than locking an uncertain send',
    async code => {
      const wrapper = mountEditor();
      await flushPromises();
      API.saveIvrDraft.mockRejectedValueOnce({
        response: { status: 409, data: { error: code } },
      });
      await wrapper
        .get('#ivr-name')
        .setValue('SYNTHETIC preserved unsaved title');
      await wrapper.get('[data-ivr-save]').trigger('click');
      await flushPromises();
      expect(wrapper.get('#ivr-name').element.value).toBe(
        'SYNTHETIC preserved unsaved title'
      );
      expect(
        wrapper.get('[data-ivr-save]').attributes('disabled')
      ).toBeUndefined();
      expect(wrapper.text()).toContain(
        locale.JRC_CONTACT_CENTER.LOCAL_IVR.ERRORS[code]
      );
    }
  );

  it('hides the editor after the native chooser denies the current unit instead of retaining private choices', async () => {
    const wrapper = mountEditor();
    await flushPromises();
    API.unitCalendars.mockRejectedValueOnce({ response: { status: 403 } });
    await wrapper.get('[data-ivr-calendar-choose]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-ivr-flow-editor]').exists()).toBe(false);
    expect(wrapper.find('[data-ivr-calendar-instant]').exists()).toBe(false);
    expect(API.previewIvrDraft).not.toHaveBeenCalled();
    expect(API.saveIvrDraft).not.toHaveBeenCalled();
  });
});
