import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import { createClosureRevisionClient } from 'dashboard/api/serviceDeskClosureRevisions';
const mocks = vi.hoisted(() => ({
  request: vi.fn(),
  publish: vi.fn(),
  session: null,
}));
vi.mock('dashboard/api/serviceDeskClosureRevisions', async original => ({
  ...(await original()),
  default: { request: (...args) => mocks.request(...args) },
}));
vi.mock('dashboard/api/serviceDeskLifecycle', () => ({
  default: { publish: (...args) => mocks.publish(...args) },
}));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
import RevisionPanel from '../ClosureRevisionPanel.vue';
const labels = messages.JRC_SERVICE_DESK.CLOSURE_REVISION;
let wrapper;
const version = id => ({
  id,
  version: Number(id),
  name: 'Política sintética',
  current: id === '2',
  definition: { sla: { mode: 'calendar_snapshot' }, transitions: [] },
});
const row = {
  id: '11',
  title: 'Chamado antigo',
  status: 'Aberto',
  reason: null,
  lock_version: 0,
};
const button = name =>
  wrapper.findAll('button').find(node => node.text() === name);
const render = async () => {
  wrapper = mount(RevisionPanel, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        Panel: { template: '<section><slot /></section>' },
        ScopeBar: {
          props: ['unitId'],
          emits: ['update:unitId'],
          template:
            '<select aria-label="Unidade" :value="unitId" @change="$emit(\'update:unitId\', $event.target.value)"><option value=""/><option value="10">Matriz</option><option value="20">Outra unidade</option></select>',
        },
        Button: {
          props: ['label', 'disabled'],
          template: '<button :disabled="disabled">{{ label }}</button>',
        },
      },
    },
  });
  await wrapper.find('select[aria-label="Unidade"]').setValue('10');
  await flushPromises();
};
const choose = async () => {
  await wrapper.find(`select[aria-label="${labels.source}"]`).setValue('1');
  await wrapper.find(`select[aria-label="${labels.target}"]`).setValue('2');
};
const review = async () => {
  await wrapper.find('input[type="checkbox"]').setValue(true);
  await wrapper.find('textarea').setValue('Revisão operacional explícita');
};
beforeEach(() => {
  localStorage.clear();
  vi.stubGlobal('crypto', { randomUUID: () => 'synthetic-ui-batch' });
  mocks.session = {
    state: reactive({
      status: 'ready',
      context: {
        account_id: '1',
        user_id: '7',
        units: [{ id: '10' }, { id: '20' }],
        capabilities: { lifecycle_policies: { publish: true } },
        effective_permissions: [
          'tickets_view_all',
          'history_view',
          'sla_view',
          'contract_conditions_view',
        ].map(k => 'jrc_service_desk_' + k),
      },
    }),
  };
  mocks.request.mockImplementation(async (_account, action) => {
    if (action === 'versions')
      return { versions: [version('2'), version('1')], total: 2 };
    if (action === '')
      return {
        items: [row, { ...row, id: '12', reason: 'terminal_ticket' }],
        total: 2,
        counts: { eligible: 1, terminal_ticket: 1 },
      };
    if (action === 'preview')
      return {
        preview: {
          receipt: 'signed-synthetic-preview',
          eligible: 1,
          blocked: 0,
          tickets: [row],
        },
      };
    if (action === 'result')
      return {
        result: {
          batch_id: 'synthetic-ui-batch',
          complete: true,
          results: [{ ticket_id: '11', status: 'applied' }],
        },
      };
    return {};
  });
});
afterEach(() => {
  wrapper?.unmount();
  vi.resetAllMocks();
  vi.unstubAllGlobals();
});
describe('administrative closure revision controls', () => {
  it('loads versions only after unit selection and never automatically publishes or applies', async () => {
    await render();
    expect(mocks.request).toHaveBeenCalledOnce();
    expect(mocks.publish).not.toHaveBeenCalled();
    expect(wrapper.find('input[type="checkbox"]').element.checked).toBe(false);
    expect(button(labels.preview).element.disabled).toBe(true);
  });
  it('separates blocked tickets and requires explicit review plus a signed preview before application', async () => {
    await render();
    await choose();
    await button(labels.list).trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(labels.reasons.terminal_ticket);
    expect(wrapper.findAll('tbody input')[1].element.disabled).toBe(true);
    await button(labels.select_page).trigger('click');
    await flushPromises();
    expect(button(labels.preview).element.disabled).toBe(true);
    await review();
    await button(labels.preview).trigger('click');
    await flushPromises();
    expect(mocks.request).toHaveBeenLastCalledWith(
      '1',
      'preview',
      expect.objectContaining({
        ticket_ids: ['11'],
        operational_review: true,
        review_reason: 'Revisão operacional explícita',
      }),
      expect.objectContaining({ method: 'post' })
    );
    expect(
      wrapper.find('[data-testid="closure-revision-preview"]').exists()
    ).toBe(true);
    expect(mocks.publish).not.toHaveBeenCalled();
  });
  it('only reports confirmation after independent readback and recovers a lost response without a second application', async () => {
    await render();
    await choose();
    await button(labels.list).trigger('click');
    await flushPromises();
    await button(labels.select_page).trigger('click');
    await review();
    await button(labels.preview).trigger('click');
    await flushPromises();
    mocks.request.mockRejectedValueOnce(new Error('lost response'));
    await button(labels.apply).trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(labels.failed);
    expect(
      wrapper.find('[data-testid="closure-revision-result"]').exists()
    ).toBe(false);
    await button(labels.recover).trigger('click');
    await flushPromises();
    expect(
      wrapper.find('[data-testid="closure-revision-result"]').text()
    ).toContain(labels.statuses.applied);
    expect(
      mocks.request.mock.calls.filter(
        call => call[3]?.key === 'synthetic-ui-batch'
      )
    ).toHaveLength(1);
  });
  it('clears the previous scope and ignores a late response after the global Account changes', async () => {
    await render();
    await choose();
    let resolve;
    mocks.request.mockReturnValueOnce(
      new Promise(done => {
        resolve = done;
      })
    );
    await button(labels.list).trigger('click');
    mocks.session.state.context = {
      ...mocks.session.state.context,
      account_id: '2',
      units: [{ id: '20' }],
    };
    await flushPromises();
    resolve({ items: [row], total: 1, counts: { eligible: 1 } });
    await flushPromises();
    expect(wrapper.text()).not.toContain('Chamado antigo');
    expect(wrapper.findAll('tbody tr')).toHaveLength(0);
  });
  it('preserves the selected Account and rejects a response from another Account in the real HTTP client', async () => {
    const http = {
      get: vi.fn().mockResolvedValue({
        data: { contract_version: 1, account_id: '99', versions: [] },
      }),
    };
    const client = createClosureRevisionClient(http);
    await expect(
      client.request('1', 'versions', { unit_id: '10' })
    ).rejects.toThrow('Foreign closure revision response');
    expect(http.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_service_desk/closure_revisions/versions',
      expect.objectContaining({ params: { unit_id: '10' } })
    );
  });
});
