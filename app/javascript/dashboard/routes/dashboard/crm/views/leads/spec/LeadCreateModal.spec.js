import { mount, flushPromises } from '@vue/test-utils';
import { leadsAPI } from 'dashboard/api/crm';
import messages from 'dashboard/i18n/locale/en/crm.json';
import LeadCreateModal from '../LeadCreateModal.vue';

vi.mock('dashboard/api/crm', () => ({ leadsAPI: { create: vi.fn() } }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const mountForm = props =>
  mount(LeadCreateModal, {
    props,
    global: {
      stubs: { Teleport: true },
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
});
