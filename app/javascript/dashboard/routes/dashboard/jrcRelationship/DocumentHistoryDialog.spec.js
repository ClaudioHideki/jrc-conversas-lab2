import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, expect, it, vi } from 'vitest';
import History from './DocumentHistoryDialog.vue';
const mocks = vi.hoisted(() => ({ history: vi.fn(), route: null }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcRelationship', () => ({
  default: { documentHistory: mocks.history },
}));
const Dialog = {
  setup(_, { expose, emit }) {
    expose({ open: vi.fn(), close: () => emit('close') });
  },
  template: '<section><slot /></section>',
};
const document = { id: 6, title: 'SYNTHETIC protected document' };
const row = {
  id: 9,
  action: 'document_metadata_updated',
  at: '2026-11-04T10:00:00Z',
  actor: { state: 'available', name: 'Native actor' },
  before: { responsible: { state: 'unassigned' }, status: 'active' },
  after: {
    responsible: { state: 'available', name: 'New documentary responsible' },
    status: 'archived',
    requirement_key: 'registration_proof',
  },
  reason: 'SYNTHETIC actual reason',
  version: null,
};
const result = { data: { payload: [row], meta: { total: 45, per_page: 20 } } };
const render = () =>
  mount(History, {
    props: {
      document,
      formatting: { locale: 'pt-BR', timeZone: 'America/Sao_Paulo' },
    },
    global: { stubs: { Dialog } },
  });
beforeEach(() => {
  mocks.route = reactive({ params: { accountId: '1400' } });
  mocks.history.mockReset().mockResolvedValue(result);
});
it('loads bounded native history and shows recorded changes, actor and reason without changing the document', async () => {
  const wrapper = render();
  await flushPromises();
  expect(mocks.history).toHaveBeenCalledWith(
    '1400',
    6,
    { kind: undefined, page: 1, per_page: 20 },
    expect.objectContaining({ signal: expect.any(AbortSignal) })
  );
  expect(wrapper.text()).toContain('SYNTHETIC actual reason');
  expect(wrapper.text()).toContain('New documentary responsible');
  expect(wrapper.text()).toContain(
    'RELATIONSHIP.V2.DOCS.NO_DOCUMENT_RESPONSIBLE'
  );
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIP.V2.DOCS.VERSIONS')
    .trigger('click');
  expect(wrapper.emitted('versions')[0]).toEqual([document]);
  wrapper.unmount();
});
it('paginates and resets page when changing the native action filter', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIP.V2.NEXT')
    .trigger('click');
  await flushPromises();
  expect(mocks.history.mock.calls.at(-1)[2].page).toBe(2);
  await wrapper
    .findAll('button')
    .find(
      button =>
        button.text() === 'RELATIONSHIP.V2.DOCS.HISTORY_FILTERS.metadata'
    )
    .trigger('click');
  await flushPromises();
  expect(mocks.history.mock.calls.at(-1)[2]).toEqual({
    kind: 'metadata',
    page: 1,
    per_page: 20,
  });
  wrapper.unmount();
});
it('clears protected rows on denial and aborts its own pending request when closed', async () => {
  const wrapper = render();
  await flushPromises();
  mocks.history.mockRejectedValue({ response: { status: 403 } });
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIP.REFRESH')
    .trigger('click');
  await flushPromises();
  expect(wrapper.text()).not.toContain('SYNTHETIC actual reason');
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(wrapper.emitted('denied')[0][0].response.status).toBe(403);
  const signal = mocks.history.mock.calls.at(-1)[3].signal;
  wrapper.unmount();
  expect(signal.aborted).toBe(true);
});
it('ignores late history after its filter changed and a newer authorized response arrived', async () => {
  let resolve;
  mocks.history.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  const wrapper = render();
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(
      button => button.text() === 'RELATIONSHIP.V2.DOCS.HISTORY_FILTERS.version'
    )
    .trigger('click');
  await flushPromises();
  resolve({
    data: {
      payload: [{ ...row, reason: 'STALE PRIVATE RESULT' }],
      meta: result.data.meta,
    },
  });
  await flushPromises();
  expect(wrapper.text()).not.toContain('STALE PRIVATE RESULT');
  expect(wrapper.text()).toContain('SYNTHETIC actual reason');
  wrapper.unmount();
});
