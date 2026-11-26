import { mount, flushPromises } from '@vue/test-utils';
import { leadsAPI } from 'dashboard/api/crm';
import CustomersAPI from 'dashboard/api/jrcCustomers';
import messages from 'dashboard/i18n/locale/en/crm.json';
import LeadCreateModal from '../LeadCreateModal.vue';
import { createStore } from 'vuex';
import { routeLocationKey } from 'vue-router';

vi.mock('dashboard/api/crm', () => ({ leadsAPI: { create: vi.fn() } }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/jrcCustomers', () => ({
  default: { contact: vi.fn(), contacts: vi.fn() },
}));

const mountForm = (props, customerMaster = false) =>
  mount(LeadCreateModal, {
    props,
    global: {
      plugins: [
        createStore({
          getters: {
            'accounts/isFeatureEnabledonAccount': () => () => customerMaster,
            getCurrentUser: () => ({
              accounts: [{ id: 1, role: 'administrator' }],
            }),
          },
        }),
      ],
      provide: { [routeLocationKey]: { params: { accountId: '1' } } },
      stubs: {
        Teleport: true,
        CompanyPicker: {
          emits: ['selected'],
          template: `<div>
            <button type="button" data-company="42" @click="$emit('selected', { id: 42, name: 'Empresa Teste' })">Empresa Teste</button>
            <button type="button" data-company="43" @click="$emit('selected', { id: 43, name: 'Outra empresa' })">Outra empresa</button>
          </div>`,
        },
      },
    },
  });

describe('Shared lead creation form', () => {
  it('prefills the selected Contact and posts the same contact ID', async () => {
    leadsAPI.create.mockResolvedValue({
      status: 201,
      data: { id: 22, contact_id: 141 },
    });
    const wrapper = mountForm({
      contact: {
        id: 141,
        name: 'Thiago',
        email: 'thiago@example.test',
        phoneNumber: '+5511988887777',
        additionalAttributes: { companyName: 'GoPure' },
      },
    });
    expect(wrapper.get('[name="name"]').element.value).toBe('Thiago');
    expect(wrapper.get('[name="company_name"]').element.value).toBe('GoPure');
    expect(wrapper.get('[name="phone"]').element.value).toBe('+5511988887777');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(leadsAPI.create).toHaveBeenCalledWith({
      lead: expect.objectContaining({
        contact_id: 141,
        name: 'Thiago',
        email: 'thiago@example.test',
      }),
    });
    expect(wrapper.emitted('created')[0][0].contact_id).toBe(141);
  });

  it('uses the same endpoint for manual creation without inventing a contact ID', async () => {
    leadsAPI.create.mockResolvedValue({
      status: 201,
      data: { id: 23, contact_id: 142 },
    });
    const wrapper = mountForm();
    await wrapper.get('[name="name"]').setValue('Pessoa nova');
    await wrapper.get('[name="email"]').setValue('nova@example.test');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(leadsAPI.create.mock.calls[0][0].lead).not.toHaveProperty(
      'contact_id'
    );
    expect(wrapper.emitted('created')[0][0].contact_id).toBe(142);
  });

  it('preserves input and displays safe feedback on an API failure', async () => {
    leadsAPI.create.mockRejectedValue({
      response: { status: 500, data: { errors: ['internal stack trace'] } },
    });
    const wrapper = mountForm();
    await wrapper.get('[name="name"]').setValue('Não perder');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      messages.CRM.LEAD_FORM.ERROR
    );
    expect(wrapper.text()).not.toContain('internal stack trace');
    expect(wrapper.get('[name="name"]').element.value).toBe('Não perder');
    expect(wrapper.emitted('created')).toBeUndefined();
    expect(wrapper.get('[type="submit"]').element.disabled).toBe(false);
  });

  it('prevents double submission while a save is pending', async () => {
    let resolve;
    leadsAPI.create.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = mountForm();
    await wrapper.get('form').trigger('submit');
    await wrapper.get('form').trigger('submit');
    expect(leadsAPI.create).toHaveBeenCalledTimes(1);
    resolve({ status: 201, data: { id: 24, contact_id: 143 } });
    await flushPromises();
  });

  it('lists people from the selected company and sends only the chosen identity', async () => {
    const person = {
      id: 88,
      name: 'Operadora Teste',
      email: 'pessoa@example.test',
      phone_number: '+551199887766',
      company_id: 42,
    };
    CustomersAPI.contacts.mockResolvedValue({ data: { payload: [person] } });
    CustomersAPI.contact.mockResolvedValue({ data: { payload: person } });
    leadsAPI.create.mockResolvedValue({ status: 201, data: { id: 92 } });
    const wrapper = mountForm(undefined, true);
    await wrapper.get('button[data-company="42"]').trigger('click');
    await flushPromises();
    expect(CustomersAPI.contacts).toHaveBeenCalledWith(
      expect.objectContaining({ company_id: 42, page: 1 }),
      { accountId: 1 }
    );
    const result = wrapper
      .findAll('button')
      .find(button => button.text().includes(person.name));
    await result.trigger('click');
    await flushPromises();
    expect(wrapper.get('[name="name"]').element.value).toBe(person.name);
    expect(wrapper.get('[name="email"]').element.value).toBe(person.email);
    expect(wrapper.get('[name="phone"]').element.value).toBe(
      person.phone_number
    );
    expect(wrapper.get('[name="email"]').element.readOnly).toBe(true);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(leadsAPI.create).toHaveBeenCalledWith({
      lead: expect.objectContaining({
        contact_id: person.id,
        company_id: 42,
        company_name: 'Empresa Teste',
        email: person.email,
      }),
    });
    wrapper.unmount();
  });

  it('discards an old search when the company changes and keeps the form open on an outside release', async () => {
    let finishFirstSearch;
    CustomersAPI.contacts.mockImplementation(({ company_id: companyId }) =>
      companyId === 42
        ? new Promise(resolve => {
            finishFirstSearch = resolve;
          })
        : Promise.resolve({ data: { payload: [] } })
    );
    const wrapper = mountForm(undefined, true);
    const switchCompany = async id => {
      await wrapper.get(`button[data-company="${id}"]`).trigger('click');
      await flushPromises();
      expect(
        wrapper.getComponent({ name: 'ContactPicker' }).props('companyId')
      ).toBe(id);
    };
    await switchCompany(42);
    await switchCompany(43);
    expect(
      CustomersAPI.contacts.mock.calls.map(([params]) => params.company_id)
    ).toEqual([42, 43]);
    finishFirstSearch({
      data: { payload: [{ id: 88, name: 'Pessoa da empresa anterior' }] },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('Pessoa da empresa anterior');
    await wrapper.get('[name="name"]').setValue('Nome para copiar');
    await wrapper.get('[name="name"]').trigger('pointerdown');
    const backdrop = wrapper.get('form').element.parentElement;
    backdrop.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    expect(wrapper.emitted('close')).toBeUndefined();
    expect(wrapper.get('[name="name"]').element.value).toBe('Nome para copiar');
    await wrapper.get('form').trigger('keydown', { key: 'Escape' });
    expect(wrapper.emitted('close')).toHaveLength(1);
    wrapper.unmount();
  });
});
