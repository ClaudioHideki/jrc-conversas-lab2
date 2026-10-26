import { beforeEach, afterEach, describe, it, expect, vi } from 'vitest';
import { reactive, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';

const mocks = vi.hoisted(() => ({
  search: vi.fn(),
  validate: vi.fn(),
  register: vi.fn(),
  link: vi.fn(),
  session: null,
  access: null,
}));
vi.mock('dashboard/api/serviceDeskRequesters', () => ({ default: mocks }));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
vi.mock('dashboard/routes/dashboard/jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ canAccess: mocks.access }),
}));
import RequesterSelect from '../RequesterSelect.vue';

const text = messages.JRC_SERVICE_DESK.REQUESTERS;
const person = (id = 20, companyId = null) => ({
  id,
  name: 'Pessoa sintética',
  company_id: companyId,
  requester_eligible: true,
  can_link: true,
});
const Button = {
  props: ['label', 'disabled', 'type'],
  template:
    '<button :type="type || \'button\'" :disabled="disabled">{{ label }}</button>',
};
const Input = {
  props: ['modelValue', 'label', 'disabled'],
  emits: ['update:modelValue'],
  template:
    '<label>{{ label }}<input :value="modelValue" :disabled="disabled" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>',
};
const LookupSelect = {
  props: [
    'modelValue',
    'companyId',
    'unitId',
    'disabled',
    'emptyText',
    'refreshKey',
  ],
  template: '<p data-lookup>{{ emptyText }}</p>',
};
let wrapper;
const button = label =>
  wrapper.findAll('button').find(node => node.text() === label);
const render = props => {
  wrapper = mount(RequesterSelect, {
    props: { companyId: 10, unitId: '1', ...props },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        Button,
        Input,
        LookupSelect,
        ServiceDeskDialog: {
          props: ['open', 'title'],
          template:
            '<section v-if="open" role="dialog" :aria-label="title"><slot /></section>',
        },
      },
    },
  });
};
beforeEach(() => {
  vi.clearAllMocks();
  mocks.access = ref(true);
  mocks.session = {
    state: reactive({
      context: {
        effective_permissions: ['jrc_service_desk_customers_view'],
        units: [{ id: '1', permissions: { create_ticket: true } }],
      },
    }),
  };
  mocks.search.mockResolvedValue({
    data: {
      items: [],
      meta: { total: 0 },
      company: { name: 'Empresa sintética Alfa' },
      can_create: true,
    },
  });
  mocks.validate.mockRejectedValue({ response: { status: 422 } });
});
afterEach(() => {
  wrapper?.unmount();
  vi.useRealTimers();
});

describe('Canonical requester intake shared by quick and advanced forms', () => {
  it('requires explicit homonym confirmation and sends it without bypassing identity checks', async () => {
    mocks.register
      .mockRejectedValueOnce({
        response: {
          data: {
            code: 'POSSIBLE_DUPLICATE',
            allow_distinct: true,
            candidates: [person()],
          },
        },
      })
      .mockResolvedValueOnce({ data: { person: person(22, 10) } });
    render();
    await button(text.new).trigger('click');
    await flushPromises();
    await wrapper.findAll('input')[0].setValue('Pessoa homônima');
    await button(text.save).trigger('click');
    await flushPromises();
    expect(wrapper.get('input[type="checkbox"]').element.checked).toBe(false);
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await button(text.save).trigger('click');
    await flushPromises();
    expect(mocks.register.mock.calls[1][0].confirm_distinct).toBe(true);
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['22']);
  });

  it('clears an open search and its people when directory permission is revoked', async () => {
    mocks.search.mockResolvedValue({
      data: { items: [person()], meta: { total: 1 }, can_create: true },
    });
    render();
    await button(text.search).trigger('click');
    await flushPromises();
    expect(wrapper.findAll('article')).toHaveLength(1);
    mocks.access.value = false;
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(mocks.link).not.toHaveBeenCalled();
  });
  it('explains an empty company and offers both integrated actions', () => {
    render();
    expect(wrapper.findComponent(LookupSelect).props('emptyText')).toBe(
      'Nenhum solicitante cadastrado para esta empresa.'
    );
    expect(button(text.search)).toBeDefined();
    expect(button(text.new)).toBeDefined();
    expect(wrapper.text()).toContain(text.separation);
  });

  it('hides write actions without master permission or without a selected company', async () => {
    render();
    mocks.access.value = false;
    await flushPromises();
    expect(button(text.new)).toBeUndefined();
    mocks.access.value = true;
    await wrapper.setProps({ companyId: null });
    expect(button(text.search)).toBeUndefined();
  });

  it('does not link before confirmation and selects the persisted canonical person', async () => {
    mocks.search.mockResolvedValue({
      data: { items: [person()], meta: { total: 1 }, can_create: true },
    });
    mocks.link.mockResolvedValue({ data: { person: person(20, 10) } });
    render();
    await button(text.search).trigger('click');
    await flushPromises();
    await button(text.link).trigger('click');
    expect(mocks.link).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain(text.confirm_help);
    await button(text.confirm_link).trigger('click');
    await flushPromises();
    expect(mocks.link).toHaveBeenCalledWith(20, {
      unit_id: '1',
      company_id: 10,
      confirm: true,
    });
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['20']);
    expect(wrapper.emitted('selected').at(-1)[0].company_id).toBe('10');
  });

  it('selects an already linked person without writing their relationship', async () => {
    mocks.search.mockResolvedValue({
      data: { items: [person(20, 10)], meta: { total: 1 }, can_create: true },
    });
    render();
    await button(text.search).trigger('click');
    await flushPromises();
    await button(text.use).trigger('click');
    expect(mocks.link).not.toHaveBeenCalled();
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['20']);
  });

  it('blocks organization, ambiguous imports and contacts belonging to another company', async () => {
    mocks.search.mockResolvedValue({
      data: {
        items: [
          {
            ...person(1),
            requester_eligible: false,
            review_reason: 'organization',
          },
          {
            ...person(2),
            requester_eligible: false,
            review_reason: 'import_review',
          },
          person(3, 99),
        ],
        meta: { total: 3 },
        can_create: true,
      },
    });
    render();
    await button(text.search).trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(text.organization);
    expect(wrapper.text()).toContain(text.import_review);
    expect(wrapper.text()).toContain(text.other_company);
    expect(
      wrapper.findAll('article button').every(node => node.element.disabled)
    ).toBe(true);
    expect(mocks.link).not.toHaveBeenCalled();
  });

  it('creates with only a name and never emits a ticket submission', async () => {
    mocks.register.mockResolvedValue({ data: { person: person(21, 10) } });
    render();
    await button(text.new).trigger('click');
    await flushPromises();
    await wrapper.findAll('input')[0].setValue('Nova pessoa sintética');
    await button(text.save).trigger('click');
    await flushPromises();
    expect(mocks.register).toHaveBeenCalledWith(
      expect.objectContaining({
        company_id: 10,
        unit_id: '1',
        contact: { name: 'Nova pessoa sintética', email: '', phone_number: '' },
        request_key: expect.any(String),
      })
    );
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['21']);
    expect(wrapper.emitted('submit')).toBeUndefined();
  });

  it('offers duplicate review and reuse without merging or retrying automatically', async () => {
    mocks.register.mockRejectedValue({
      response: {
        data: { code: 'POSSIBLE_DUPLICATE', candidates: [person()] },
      },
    });
    render();
    await button(text.new).trigger('click');
    await flushPromises();
    await wrapper.findAll('input')[0].setValue('Pessoa já cadastrada');
    await button(text.save).trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(text.duplicate);
    expect(wrapper.findAll('article')).toHaveLength(1);
    expect(mocks.register).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('keeps the request key after a transient response failure to avoid duplicate retries', async () => {
    mocks.register.mockRejectedValue(new Error('timeout'));
    render();
    await button(text.new).trigger('click');
    await flushPromises();
    await wrapper.findAll('input')[0].setValue('Pessoa sintética');
    await button(text.save).trigger('click');
    await flushPromises();
    const first = mocks.register.mock.calls[0][0].request_key;
    await button(text.save).trigger('click');
    await flushPromises();
    expect(mocks.register.mock.calls[1][0].request_key).toBe(first);
  });

  it('clears an invalid requester after a company switch without modifying any Contact', async () => {
    render({ modelValue: '20' });
    await wrapper.setProps({ companyId: 11 });
    await flushPromises();
    expect(mocks.validate).toHaveBeenCalledWith('20', {
      unit_id: '1',
      company_id: 11,
    });
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['']);
    expect(wrapper.text()).toContain(text.company_changed);
    expect(mocks.link).not.toHaveBeenCalled();
    expect(mocks.register).not.toHaveBeenCalled();
  });

  it('retains the previous requester when the backend confirms a valid link', async () => {
    mocks.validate.mockResolvedValue({ data: { person: person(20, 11) } });
    render({ modelValue: '20' });
    await wrapper.setProps({ companyId: 11 });
    await flushPromises();
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['20']);
  });

  it('ignores a stale company response that arrives after a later selection', async () => {
    let first;
    mocks.validate
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            first = resolve;
          })
      )
      .mockResolvedValueOnce({ data: { person: person(20, 12) } });
    render({ modelValue: '20' });
    await wrapper.setProps({ companyId: 11 });
    await wrapper.setProps({ companyId: 12 });
    await flushPromises();
    first({ data: { person: person(20, 11) } });
    await flushPromises();
    expect(wrapper.emitted('selected')).toHaveLength(1);
    expect(wrapper.emitted('selected')[0][0].company_id).toBe('12');
  });

  it('prevents a late registration result from selecting a person in another company', async () => {
    let finish;
    mocks.register.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    render();
    await button(text.new).trigger('click');
    await flushPromises();
    await wrapper.findAll('input')[0].setValue('Pessoa sintética');
    await button(text.save).trigger('click');
    await wrapper.setProps({ companyId: 11 });
    finish({ data: { person: person(21, 10) } });
    await flushPromises();
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('enforces backend write permission even when the modal is open', async () => {
    mocks.search.mockResolvedValue({
      data: { items: [], meta: { total: 0 }, can_create: false },
    });
    render();
    await button(text.new).trigger('click');
    await flushPromises();
    await wrapper.findAll('input')[0].setValue('Pessoa sintética');
    expect(button(text.save).element.disabled).toBe(true);
    expect(mocks.register).not.toHaveBeenCalled();
  });
});
