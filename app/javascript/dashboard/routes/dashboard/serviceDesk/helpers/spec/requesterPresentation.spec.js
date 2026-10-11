import { beforeEach, describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import { nextTick, reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import HistoryEventCard from '../../components/HistoryEventCard.vue';
import LookupSelect from '../../components/LookupSelect.vue';
import TicketSummary from '../../components/TicketSummary.vue';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import { decodeContext, decodeRecord } from '../contracts';
import { normalizeQuery } from '../query';
import { contextPayload, identity, ticket } from '../../__tests__/fixtures';

const context = () => decodeContext(contextPayload(), identity);
const lookup = vi.hoisted(() => ({ session: null }));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => lookup.session,
}));
beforeEach(() => {
  lookup.session = {
    state: reactive({ status: 'ready', context: context() }),
    resource: () => ({ items: [], status: 'ready', meta: null }),
    load: vi.fn(),
    resetResource: vi.fn(),
  };
});

describe('readable Service Desk projections', () => {
  it('shows event labels and values without rendering JSON or unrecognized fields', () => {
    const row = ticket();
    const event = {
      account_id: row.account_id,
      unit_id: row.unit_id,
      ticket_id: row.id,
      event_type: 'ticket_created',
      created_at: '2026-10-11T12:00:00Z',
      author: { name: 'Operador' },
      data: { priority_id: row.priority.id, secret: 'hidden-value' },
    };
    const original = JSON.stringify(event);
    const wrapper = mount(HistoryEventCard, {
      props: { event, ticket: row },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'pt_BR',
            messages: { pt_BR: messages },
          }),
        ],
      },
    });
    expect(wrapper.text()).toContain('Prioridade');
    expect(wrapper.text()).toContain(row.priority.name);
    expect(wrapper.text()).not.toContain('hidden-value');
    expect(wrapper.find('pre').exists()).toBe(false);
    expect(JSON.stringify(event)).toBe(original);
    wrapper.unmount();
  });

  it('retains the permitted requester phone and discards unrelated contact fields', () => {
    const source = {
      ...ticket(),
      requester: {
        id: '33',
        name: 'Cliente',
        phone_number: '+5511999990001',
        secret: 'hidden',
      },
    };
    const row = decodeRecord(source, context(), 'tickets');
    expect(row.requester).toEqual({
      id: '33',
      name: 'Cliente',
      phone_number: '+5511999990001',
    });
    expect(() =>
      decodeRecord({ ...source, account_id: '999' }, context(), 'tickets')
    ).toThrow();
  });

  it('accepts only canonical team IDs in assignee lookup queries', () => {
    expect(normalizeQuery({ team_id: '12' }, 'assignees').team_id).toBe('12');
    expect(() => normalizeQuery({ team_id: '01' }, 'assignees')).toThrow();
    expect(() => normalizeQuery({ team_id: ['12'] }, 'assignees')).toThrow();
    expect(() => normalizeQuery({ team_id: '12' }, 'requesters')).toThrow();
    expect(() => normalizeQuery({ team_id: '12' })).toThrow();
  });

  it('shows the authorized requester phone under the name and hides it after permission revocation', async () => {
    const wrapper = mount(LookupSelect, {
      props: {
        resource: 'requesters',
        unitId: '10',
        modelValue: '33',
        label: 'Solicitante',
        currentName: 'Cliente',
        currentPhone: '+5511999990001',
      },
      global: { stubs: { Select: true, Input: true } },
    });
    expect(wrapper.text()).toContain('+5511999990001');
    await wrapper.setProps({ unitId: '999' });
    expect(wrapper.text()).not.toContain('+5511999990001');
    await wrapper.setProps({ unitId: '10' });
    lookup.session.state.context.capabilities.requesters.index = false;
    await nextTick();
    expect(wrapper.text()).not.toContain('+5511999990001');
    wrapper.unmount();
  });

  it('shows the same native phone in the ticket summary without inventing a missing phone', async () => {
    const wrapper = mount(TicketSummary, {
      props: {
        ticket: ticket({
          requester: {
            id: '33',
            name: 'Cliente',
            phone_number: '+5511999990001',
          },
        }),
      },
    });
    expect(wrapper.text()).toContain('Cliente');
    expect(wrapper.text()).toContain('+5511999990001');
    await wrapper.setProps({
      ticket: ticket({ requester: { id: '33', name: 'Cliente' } }),
    });
    expect(wrapper.text()).not.toContain('+5511999990001');
    wrapper.unmount();
  });

  it('reloads the assignee lookup with the selected team in the authorized unit', async () => {
    const wrapper = mount(LookupSelect, {
      props: {
        resource: 'assignees',
        unitId: '10',
        teamId: '12',
        label: 'Responsável',
      },
      global: { stubs: { Select: true, Input: true } },
    });
    expect(lookup.session.load).toHaveBeenLastCalledWith(
      expect.any(String),
      'assignees',
      {
        unit_id: '10',
        q: '',
        page: 1,
        per_page: 20,
        team_id: '12',
      }
    );
    await wrapper.setProps({ teamId: '13' });
    expect(lookup.session.load).toHaveBeenLastCalledWith(
      expect.any(String),
      'assignees',
      {
        unit_id: '10',
        q: '',
        page: 1,
        per_page: 20,
        team_id: '13',
      }
    );
    await wrapper.setProps({ teamId: '' });
    expect(lookup.session.load).toHaveBeenLastCalledWith(
      expect.any(String),
      'assignees',
      {
        unit_id: '10',
        q: '',
        page: 1,
        per_page: 20,
      }
    );
    wrapper.unmount();
  });
});
