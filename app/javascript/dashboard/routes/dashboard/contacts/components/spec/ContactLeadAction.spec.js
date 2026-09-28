import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { leadsAPI } from 'dashboard/api/crm';
import ContactLeadAction from '../ContactLeadAction.vue';

vi.mock('vue-router', () => ({ useRoute: vi.fn(), useRouter: vi.fn() }));
vi.mock('dashboard/api/crm', () => ({
  leadsAPI: { forContact: vi.fn(), fromContact: vi.fn() },
}));

describe('Contact → Lead action', () => {
  let route;
  let router;
  let wrapper;
  beforeEach(() => {
    route = reactive({ params: { accountId: '1' } });
    router = { push: vi.fn() };
    useRoute.mockReturnValue(route);
    useRouter.mockReturnValue(router);
    leadsAPI.forContact.mockResolvedValue({ data: { lead: null } });
    leadsAPI.fromContact.mockResolvedValue({
      data: { lead: { id: 7 }, created: true },
    });
  });
  afterEach(() => wrapper?.unmount());

  it('creates from the selected contact once, then opens the existing CRM detail', async () => {
    wrapper = mount(ContactLeadAction, { props: { contact: { id: 42 } } });
    await flushPromises();
    let finish;
    leadsAPI.fromContact.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    await wrapper.get('button').trigger('click');
    await wrapper.get('button').trigger('click');
    expect(leadsAPI.fromContact).toHaveBeenCalledTimes(1);
    expect(leadsAPI.fromContact).toHaveBeenCalledWith(42);
    finish({ data: { lead: { id: 7 } } });
    await flushPromises();
    expect(router.push).toHaveBeenCalledWith({
      name: 'crm_leads',
      params: { accountId: '1' },
      query: { leadId: 7 },
    });
    await wrapper.get('button').trigger('click');
    expect(leadsAPI.fromContact).toHaveBeenCalledTimes(1);
  });

  it('opens a previously linked lead without creating it', async () => {
    leadsAPI.forContact.mockResolvedValue({ data: { lead: { id: 8 } } });
    wrapper = mount(ContactLeadAction, { props: { contact: { id: 42 } } });
    await flushPromises();
    expect(wrapper.text()).toContain('Abrir lead');
    await wrapper.get('button').trigger('click');
    expect(leadsAPI.fromContact).not.toHaveBeenCalled();
    expect(router.push).toHaveBeenCalledWith(
      expect.objectContaining({ query: { leadId: 8 } })
    );
  });

  it.each([401, 403])(
    'hides the action when the API denies CRM access (%s)',
    async status => {
      leadsAPI.forContact.mockRejectedValue({ response: { status } });
      wrapper = mount(ContactLeadAction, { props: { contact: { id: 42 } } });
      await flushPromises();
      expect(wrapper.find('button').exists()).toBe(false);
      expect(leadsAPI.fromContact).not.toHaveBeenCalled();
    }
  );

  it.each([404, 409, 500])(
    'does not create a duplicate after a failed lookup (%s)',
    async status => {
      leadsAPI.forContact.mockRejectedValueOnce({ response: { status } });
      wrapper = mount(ContactLeadAction, { props: { contact: { id: 42 } } });
      await flushPromises();
      expect(wrapper.get('[role="alert"]').text()).not.toBe('');
      await wrapper.get('button').trigger('click');
      await flushPromises();
      expect(leadsAPI.forContact).toHaveBeenCalledTimes(2);
      expect(leadsAPI.fromContact).not.toHaveBeenCalled();
    }
  );

  it('ignores lookup responses for the previous contact/account', async () => {
    let oldResponse;
    leadsAPI.forContact.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          oldResponse = resolve;
        })
    );
    wrapper = mount(ContactLeadAction, { props: { contact: { id: 42 } } });
    route.params.accountId = '2';
    await wrapper.setProps({ contact: { id: 43 } });
    await flushPromises();
    oldResponse({ data: { lead: { id: 999 } } });
    await flushPromises();
    expect(wrapper.text()).toContain('Criar lead');
    expect(wrapper.text()).not.toContain('Abrir lead');
  });

  it('does not navigate for an old creation response after switching contact', async () => {
    let oldResponse;
    wrapper = mount(ContactLeadAction, { props: { contact: { id: 42 } } });
    await flushPromises();
    leadsAPI.fromContact.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          oldResponse = resolve;
        })
    );
    await wrapper.get('button').trigger('click');
    await wrapper.setProps({ contact: { id: 43 } });
    oldResponse({ data: { lead: { id: 999 } } });
    await flushPromises();
    expect(router.push).not.toHaveBeenCalled();
  });
});
