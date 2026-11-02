import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import TicketAssetLinks from '../TicketAssetLinks.vue';
import { deferred } from '../../__tests__/fixtures';

const mocks = vi.hoisted(() => ({
  session: null,
  list: vi.fn(),
  read: vi.fn(),
  linkTickets: vi.fn(),
  unlinkTicket: vi.fn(),
}));
vi.mock('dashboard/api/serviceDeskResources', () => ({ default: mocks }));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
const labels = messages.JRC_SERVICE_DESK;
const asset = (extra = {}) => ({
  id: '8',
  account_id: '1',
  unit_id: '2',
  resource_kind: 'asset',
  name: 'Roteador autorizado',
  code: 'RO-8',
  state: 'active',
  priority: 'normal',
  lock_version: 0,
  history: [],
  details: {},
  ticket_ids: [],
  permissions: { show: true, update: true, destroy: true },
  ...extra,
});
const payload = items => ({
  contract_version: 1,
  account_id: '1',
  items,
  meta: { page: 1, per_page: 20, total: items.length },
});
let wrapper;
const build = (update = true) => {
  wrapper = mount(TicketAssetLinks, {
    props: {
      ticket: {
        id: '20',
        account_id: '1',
        unit_id: '2',
        permissions: { show: true, update },
      },
    },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        Button: {
          props: ['label', 'disabled', 'type'],
          template:
            '<button :type="type || \'button\'" :disabled="disabled">{{ label }}</button>',
        },
        ServiceDeskDialog: {
          props: ['open'],
          template: '<div v-if="open" data-dialog><slot /></div>',
        },
        State: true,
        Pagination: true,
      },
    },
  });
  return wrapper;
};
const click = async text => {
  const button = wrapper.findAll('button').find(item => item.text() === text);
  expect(button).toBeDefined();
  await button.trigger('click');
  await flushPromises();
};
beforeEach(() => {
  mocks.session = {
    state: reactive({
      status: 'ready',
      context: {
        account_id: '1',
        units: [{ id: '2' }],
        capabilities: { incidents: { index: true } },
      },
    }),
  };
  mocks.list.mockResolvedValue(payload([]));
  mocks.linkTickets.mockResolvedValue({ applied: true, account_id: '1' });
  mocks.unlinkTicket.mockResolvedValue({ applied: true, account_id: '1' });
});
afterEach(() => wrapper?.unmount());

describe('ticket equipment relationships', () => {
  it('lists only this ticket and confirms a new link through an independent read', async () => {
    const readback = deferred();
    mocks.list.mockImplementation(async (_account, query) =>
      payload(query.ticket_id ? [] : [asset()])
    );
    mocks.read.mockReturnValue(readback.promise);
    build();
    await flushPromises();
    expect(mocks.list).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({
        unit_id: '2',
        ticket_id: '20',
        resource_kind: 'asset',
      }),
      expect.any(AbortSignal)
    );
    await click(labels.REDESIGN_DETAIL.link_asset);
    await click(labels.TICKET.link);
    expect(mocks.linkTickets).toHaveBeenCalledWith(
      '1',
      '2',
      expect.objectContaining({ id: '8', lock_version: 0 }),
      ['20'],
      expect.any(AbortSignal)
    );
    expect(wrapper.find('[data-dialog]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain(labels.COCKPIT.saved);
    readback.resolve({
      resource: asset({ ticket_ids: ['20'], lock_version: 1 }),
    });
    await flushPromises();
    expect(wrapper.find('[data-dialog]').exists()).toBe(false);
    expect(wrapper.text()).toContain(labels.COCKPIT.saved);
  });

  it('requires confirmation before unlinking and verifies the resulting relationship', async () => {
    mocks.list.mockResolvedValue(payload([asset({ ticket_ids: ['20'] })]));
    mocks.read.mockResolvedValue({ resource: asset({ lock_version: 1 }) });
    build();
    await flushPromises();
    await click(labels.REDESIGN_DETAIL.unlink_asset);
    expect(mocks.unlinkTicket).not.toHaveBeenCalled();
    mocks.list.mockResolvedValue(payload([]));
    await click(labels.REDESIGN_DETAIL.confirm_unlink);
    expect(mocks.unlinkTicket).toHaveBeenCalledWith(
      '1',
      '2',
      expect.objectContaining({ id: '8' }),
      '20',
      expect.any(AbortSignal)
    );
    expect(wrapper.text()).toContain(labels.REDESIGN_DETAIL.no_assets);
    expect(wrapper.text()).toContain(labels.COCKPIT.saved);
  });

  it('never replaces newer search results with a slower previous search', async () => {
    const slow = deferred();
    mocks.list.mockImplementation(async (_account, query) => {
      if (query.ticket_id) return payload([]);
      if (query.query === 'antigo') return slow.promise;
      return payload([
        asset({
          name: query.query === 'atual' ? 'Resultado atual' : 'Busca inicial',
        }),
      ]);
    });
    build();
    await flushPromises();
    await click(labels.REDESIGN_DETAIL.link_asset);
    await wrapper.find('input').setValue('antigo');
    await wrapper.find('form').trigger('submit');
    await wrapper.find('input').setValue('atual');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    slow.resolve(payload([asset({ name: 'Resultado antigo' })]));
    await flushPromises();
    expect(wrapper.text()).toContain('Resultado atual');
    expect(wrapper.text()).not.toContain('Resultado antigo');
  });

  it('rejects a positive acknowledgement when the independent read lacks the link', async () => {
    mocks.list.mockImplementation(async (_account, query) =>
      payload(query.ticket_id ? [] : [asset()])
    );
    mocks.read.mockResolvedValue({ resource: asset() });
    build();
    await flushPromises();
    await click(labels.REDESIGN_DETAIL.link_asset);
    await click(labels.TICKET.link);
    expect(wrapper.find('[data-dialog]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain(labels.COCKPIT.saved);
    expect(wrapper.text()).toContain(labels.COCKPIT.error);
  });

  it('keeps read-only tickets without relationship mutation controls', async () => {
    mocks.list.mockResolvedValue(payload([asset({ ticket_ids: ['20'] })]));
    build(false);
    await flushPromises();
    expect(wrapper.text()).toContain('Roteador autorizado');
    expect(wrapper.findAll('button')).toHaveLength(0);
    expect(mocks.linkTickets).not.toHaveBeenCalled();
  });

  it('discards a link response after access to the ticket unit is revoked', async () => {
    const response = deferred();
    mocks.list.mockImplementation(async (_account, query) =>
      payload(query.ticket_id ? [] : [asset()])
    );
    mocks.linkTickets.mockReturnValue(response.promise);
    build();
    await flushPromises();
    await click(labels.REDESIGN_DETAIL.link_asset);
    await click(labels.TICKET.link);
    mocks.session.state.context = { ...mocks.session.state.context, units: [] };
    await flushPromises();
    response.resolve({ applied: true, account_id: '1' });
    await flushPromises();
    expect(mocks.read).not.toHaveBeenCalled();
    expect(wrapper.text()).not.toContain(labels.COCKPIT.saved);
  });
});
