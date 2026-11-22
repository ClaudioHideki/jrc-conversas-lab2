import { afterEach, describe, expect, it, vi } from 'vitest';
import { computed, defineComponent, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import locale from 'dashboard/i18n/locale/en/jrcContactCenter.json';
import CalendarIvrUsages from 'dashboard/routes/dashboard/jrcContactCenter/components/CalendarIvrUsages.vue';

const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { calendarIvrUsages: vi.fn() },
}));
const Dialog = defineComponent({
  props: { useForm: { type: Boolean, default: true } },
  emits: ['close'],
  setup(props, { expose, emit }) {
    const visible = ref(false);
    const close = () => {
      visible.value = false;
      emit('close');
    };
    expose({
      open: () => {
        visible.value = true;
      },
      close,
    });
    return {
      visible,
      close,
      tag: computed(() => (props.useForm ? 'form' : 'div')),
    };
  },
  template:
    '<component :is="tag" v-if="visible" role="dialog"><slot /><button data-close @click="close"></button></component>',
});
const calendar = '11111111-1111-4111-8111-111111111111';
const payload = (page = 1) => ({
  account_id: '1',
  calendar_id: calendar,
  unit_id: '7',
  calendar_digest: 'a'.repeat(64),
  local_only: true,
  pabx_confirmed: false,
  coverage: 'current_local_ivr_drafts_only',
  provider_configuration_verified: false,
  items: [
    {
      draft_id: String(40 + page),
      version_id: String(50 + page),
      draft_revision: 2,
      name: 'SYNTHETIC visible URA',
      unit_id: '7',
      status: 'draft',
      local_only: true,
      provider_applied: false,
      references: [
        {
          node_id: 'hours',
          sha256: 'a'.repeat(64),
          unit_revision: 'b'.repeat(64),
          calendar_changed: false,
        },
      ],
    },
  ],
  meta: { page, per_page: 10, total: 11, pages: 2 },
});
const wrappers = [];
const setup = (props = {}) => {
  const wrapper = mount(CalendarIvrUsages, {
    props: {
      accountId: '1',
      unitId: '7',
      calendarId: calendar,
      contextKey: 'SYNTHETIC actor revision 1',
      canManage: true,
      ...props,
    },
    global: {
      stubs: { Dialog },
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: locale } }),
      ],
    },
  });
  wrappers.push(wrapper);
  return wrapper;
};
const open = async wrapper => {
  await wrapper.get('[data-calendar-ivr-usages-open]').trigger('click');
  await flushPromises();
};
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
  vi.resetAllMocks();
});

describe('authorized calendar current-local-URA inventory, mocked transport only', () => {
  it('requests only after explicit opening and identifies limited local coverage in Portuguese', async () => {
    API.calendarIvrUsages.mockResolvedValue({ data: payload() });
    const wrapper = setup();
    expect(API.calendarIvrUsages).not.toHaveBeenCalled();
    await open(wrapper);
    expect(API.calendarIvrUsages).toHaveBeenCalledExactlyOnceWith(
      '1',
      '7',
      calendar,
      {
        q: '',
        status: 'all',
        page: 1,
        per_page: 10,
      }
    );
    expect(wrapper.get('[data-calendar-ivr-usages]').text()).toContain(
      'Não comprova configuração ou uso no PABX'
    );
    expect(wrapper.get('[data-calendar-ivr-draft="41"]').text()).toContain(
      'SYNTHETIC visible URA'
    );
    expect(wrapper.text()).toContain('a'.repeat(64));
  });
  it('does not call any API without configure access', async () => {
    const wrapper = setup({ canManage: false });
    await open(wrapper);
    expect(API.calendarIvrUsages).not.toHaveBeenCalled();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  });
  it('replaces rows on real requested pages and preserves filter selectors', async () => {
    API.calendarIvrUsages.mockImplementation((account, unit, id, params) =>
      Promise.resolve({ data: payload(params.page) })
    );
    const wrapper = setup();
    await open(wrapper);
    await wrapper.get('[data-calendar-ivr-query]').setValue('SYNTHETIC');
    await wrapper.get('[data-calendar-ivr-status]').setValue('archived');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    await wrapper.get('[data-calendar-ivr-next]').trigger('click');
    await flushPromises();
    expect(API.calendarIvrUsages).toHaveBeenLastCalledWith('1', '7', calendar, {
      q: 'SYNTHETIC',
      status: 'archived',
      page: 2,
      per_page: 10,
    });
    expect(wrapper.find('[data-calendar-ivr-draft="41"]').exists()).toBe(false);
    expect(wrapper.find('[data-calendar-ivr-draft="42"]').exists()).toBe(true);
    await wrapper.get('[data-calendar-ivr-clear]').trigger('click');
    await flushPromises();
    expect(API.calendarIvrUsages).toHaveBeenLastCalledWith('1', '7', calendar, {
      q: '',
      status: 'all',
      page: 1,
      per_page: 10,
    });
  });
  it('distinguishes a genuine scoped empty result from errors and provider absence', async () => {
    const data = payload();
    data.items = [];
    data.meta = { page: 1, per_page: 10, total: 0, pages: 0 };
    API.calendarIvrUsages.mockResolvedValue({ data });
    const wrapper = setup();
    await open(wrapper);
    expect(wrapper.get('[data-calendar-ivr-empty]').text()).toContain(
      'com estes filtros'
    );
    expect(wrapper.text()).toContain('números externos não são consultados');
    expect(wrapper.find('nav').exists()).toBe(false);
  });
  it('shows an archived head and a changed source without replacing its historical hash', async () => {
    const data = payload();
    data.items[0].status = 'archived';
    data.items[0].references[0].calendar_changed = true;
    API.calendarIvrUsages.mockResolvedValue({ data });
    const wrapper = setup();
    await open(wrapper);
    const row = wrapper.get('[data-calendar-ivr-draft]');
    expect(row.text()).toContain('Arquivada internamente');
    expect(row.text()).toContain('mantém seu snapshot histórico');
    expect(row.text()).toContain('a'.repeat(64));
  });
  it('retries only the failed read after explicit action, without inventing a successful empty result', async () => {
    API.calendarIvrUsages
      .mockRejectedValueOnce(new Error('SYNTHETIC network'))
      .mockResolvedValueOnce({ data: payload() });
    const wrapper = setup();
    await open(wrapper);
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(wrapper.find('[data-calendar-ivr-empty]').exists()).toBe(false);
    expect(API.calendarIvrUsages).toHaveBeenCalledTimes(1);
    await wrapper.get('[data-calendar-ivr-retry]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-calendar-ivr-draft]').exists()).toBe(true);
  });
  it.each([401, 403, 404])(
    'closes, forgets data and reports native denial %s',
    async status => {
      API.calendarIvrUsages.mockRejectedValue({ response: { status } });
      const wrapper = setup();
      await open(wrapper);
      expect(wrapper.emitted('denied')).toHaveLength(1);
      expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
      expect(wrapper.find('[data-calendar-ivr-draft]').exists()).toBe(false);
    }
  );
  it.each([
    ['account_id', '2'],
    ['unit_id', '8'],
    ['calendar_id', 'SYNTHETIC foreign'],
    ['coverage', 'SYNTHETIC provider'],
    ['provider_configuration_verified', true],
    ['local_only', false],
    ['pabx_confirmed', true],
    ['calendar_digest', 'invalid'],
  ])(
    'rejects mismatched response %s without displaying its rows',
    async (key, value) => {
      const data = payload();
      data[key] = value;
      API.calendarIvrUsages.mockResolvedValue({ data });
      const wrapper = setup();
      await open(wrapper);
      expect(wrapper.find('[role="alert"]').exists()).toBe(true);
      expect(wrapper.find('[data-calendar-ivr-draft]').exists()).toBe(false);
    }
  );
  it.each([
    { accountId: '2' },
    { unitId: '8' },
    { calendarId: '22222222-2222-4222-8222-222222222222' },
    { contextKey: 'SYNTHETIC profile changed' },
    { canManage: false },
  ])('ignores late private responses after context change %s', async change => {
    let resolve;
    API.calendarIvrUsages.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = setup();
    await wrapper.get('[data-calendar-ivr-usages-open]').trigger('click');
    await wrapper.setProps(change);
    resolve({ data: payload() });
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.find('[data-calendar-ivr-draft]').exists()).toBe(false);
    expect(push).not.toHaveBeenCalled();
  });
  it('ignores an old answer after close and reopen even for the same calendar', async () => {
    let resolve;
    const newest = payload();
    newest.items[0].draft_id = '42';
    API.calendarIvrUsages
      .mockImplementationOnce(
        () =>
          new Promise(done => {
            resolve = done;
          })
      )
      .mockResolvedValueOnce({ data: newest });
    const wrapper = setup();
    await wrapper.get('[data-calendar-ivr-usages-open]').trigger('click');
    await wrapper.get('[data-close]').trigger('click');
    await open(wrapper);
    resolve({ data: payload() });
    await flushPromises();
    expect(wrapper.find('[data-calendar-ivr-draft="41"]').exists()).toBe(false);
    expect(wrapper.find('[data-calendar-ivr-draft="42"]').exists()).toBe(true);
  });
  it('rejects duplicate logical drafts instead of presenting inflated inventory coverage', async () => {
    const data = payload();
    data.items.push(structuredClone(data.items[0]));
    API.calendarIvrUsages.mockResolvedValue({ data });
    const wrapper = setup();
    await open(wrapper);
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(wrapper.find('[data-calendar-ivr-draft]').exists()).toBe(false);
  });
  it('navigates through the existing authorized list with unit and name selectors only', async () => {
    API.calendarIvrUsages.mockResolvedValue({ data: payload() });
    const wrapper = setup();
    await open(wrapper);
    await wrapper.get('[data-calendar-ivr-list]').trigger('click');
    expect(push).toHaveBeenCalledExactlyOnceWith({
      path: '/app/accounts/1/contact-center/ura',
      query: { ivr_unit: '7', ivr_q: 'SYNTHETIC visible URA', ivr_page: '1' },
    });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  });

  it('keeps the native list query bounded without splitting Unicode or claiming exact direct record opening', async () => {
    const data = payload();
    data.items[0].name = '🙂'.repeat(160);
    API.calendarIvrUsages.mockResolvedValue({ data });
    const wrapper = setup();
    await open(wrapper);
    await wrapper.get('[data-calendar-ivr-list]').trigger('click');
    expect(push).toHaveBeenCalledExactlyOnceWith({
      path: '/app/accounts/1/contact-center/ura',
      query: { ivr_unit: '7', ivr_q: '🙂'.repeat(100), ivr_page: '1' },
    });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  });

  it('keeps the native Dialog outer container out of form mode so the search has exactly one form', async () => {
    API.calendarIvrUsages.mockResolvedValue({ data: payload() });
    const wrapper = setup();
    await open(wrapper);
    expect(wrapper.getComponent(Dialog).props('useForm')).toBe(false);
    expect(wrapper.findAll('form')).toHaveLength(1);
    expect(wrapper.get('[data-calendar-ivr-filter]').attributes('type')).toBe(
      'submit'
    );
  });
});
