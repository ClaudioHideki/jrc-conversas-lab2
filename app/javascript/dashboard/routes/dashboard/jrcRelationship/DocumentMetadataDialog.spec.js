import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, expect, it, vi } from 'vitest';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/en/relationship.json';
import Component from './DocumentMetadataDialog.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  documentResponsibles: vi.fn(),
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks }));
const Dialog = {
  setup(_, { expose, emit }) {
    expose({ open: vi.fn(), close: () => emit('close') });
  },
  template: '<section><slot /></section>',
};
const record = {
  id: 6,
  revision: 2,
  status: 'active',
  category: 'registration',
  responsible: { id: 7, name: 'Previous responsible' },
};
const render = () =>
  mount(Component, {
    props: { document: record },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
      stubs: { Dialog },
    },
  });
beforeEach(() => {
  mocks.route = reactive({ params: { accountId: '1400' } });
  mocks.documentResponsibles.mockReset().mockResolvedValue({
    data: {
      payload: [
        { id: 8, name: 'Eligible responsible', eligible: true },
        { id: 9, name: 'Inactive', eligible: false },
      ],
      meta: { total: 3, per_page: 2 },
    },
  });
});
it('loads native eligible options and sends explicit responsibility, status, reason and server revision without uploader/portfolio changes', async () => {
  const wrapper = render();
  await flushPromises();
  expect(mocks.documentResponsibles).toHaveBeenCalledWith(
    '1400',
    6,
    { q: '', page: 1 },
    expect.objectContaining({ signal: expect.any(AbortSignal) })
  );
  expect(wrapper.get('option[value="9"]').element.disabled).toBe(true);
  await wrapper.findAll('select')[0].setValue('8');
  await wrapper.findAll('select')[1].setValue('archived');
  await wrapper.get('textarea').setValue('Explicit responsibility review');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0]).toEqual({
    requirement_key: '',
    responsible_id: 8,
    status: 'archived',
    revision: 2,
    reason: 'Explicit responsibility review',
  });
  wrapper.unmount();
});
it('searches and paginates without submitting an unrelated metadata update', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(row => row.text() === 'Próxima')
    .trigger('click');
  await flushPromises();
  expect(mocks.documentResponsibles.mock.calls.at(-1)[2].page).toBe(2);
  await wrapper.get('input').setValue('Eligible');
  await wrapper
    .findAll('button')
    .find(row => row.text() === 'Pesquisar')
    .trigger('click');
  await flushPromises();
  expect(mocks.documentResponsibles.mock.calls.at(-1)[2]).toEqual({
    q: 'Eligible',
    page: 1,
  });
  expect(wrapper.emitted('save')).toBeUndefined();
  wrapper.unmount();
});
it('keeps save disabled after permission denial and aborts pending options on unmount', async () => {
  mocks.documentResponsibles.mockRejectedValue({ response: { status: 403 } });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(wrapper.get('button[type="submit"]').element.disabled).toBe(true);
  const signal = mocks.documentResponsibles.mock.calls[0][3].signal;
  wrapper.unmount();
  expect(signal.aborted).toBe(true);
});

it('allows correcting and retrying a rejected metadata form while preserving the server revision', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.setProps({ error: 'Invalid reason' });
  await wrapper.get('textarea').setValue('Corrected reason');
  expect(wrapper.get('button[type="submit"]').element.disabled).toBe(false);
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0].revision).toBe(2);
  wrapper.unmount();
});
