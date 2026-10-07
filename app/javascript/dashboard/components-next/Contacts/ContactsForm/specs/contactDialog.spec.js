import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import CreateNewContactDialog from '../CreateNewContactDialog.vue';

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: ref({ id: 1 }),
    isCloudFeatureEnabled: () => false,
  }),
}));

describe('the shared contact dialog in a conversation', () => {
  let wrapper;
  beforeEach(() => {
    sessionStorage.clear();
    HTMLDialogElement.prototype.showModal = function showModal() {
      this.setAttribute('open', '');
    };
    HTMLDialogElement.prototype.close = function close() {
      this.removeAttribute('open');
    };
  });
  afterEach(() => {
    wrapper?.unmount();
    document.body.innerHTML = '';
    sessionStorage.clear();
  });

  it.each([
    null,
    { firstName: 'Rascunho', additionalAttributes: {} },
    {
      firstName: 'Rascunho válido',
      additionalAttributes: {
        city: 'São Paulo',
        description: 'Dados válidos do rascunho',
      },
    },
  ])('renders the form and submits with a previous draft: %s', async draft => {
    if (draft) {
      sessionStorage.setItem(
        'jrc:draft:account:1:user:7:crm:native_contact',
        JSON.stringify({ version: 1, data: draft })
      );
    }
    const store = createStore({
      getters: { getCurrentUser: () => ({ id: 7 }) },
      modules: {
        contacts: { namespaced: true, getters: { getUIFlags: () => ({}) } },
        accounts: { namespaced: true, getters: { isRTL: () => false } },
      },
    });
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        {
          path: '/app/accounts/:accountId/conversations/:id',
          component: { template: '<div />' },
        },
      ],
    });
    await router.push('/app/accounts/1/conversations/45');
    wrapper = mount(CreateNewContactDialog, {
      attachTo: document.body,
      global: {
        plugins: [
          store,
          router,
          createI18n({
            legacy: false,
            missingWarn: false,
            fallbackWarn: false,
            messages: { en: {} },
          }),
        ],
        stubs: {
          PhoneNumberInput: true,
          CompanySelector: true,
          ComboBox: true,
        },
      },
    });
    wrapper.vm.open();
    await flushPromises();
    expect(document.querySelector('dialog input')).not.toBeNull();
    expect(document.querySelector('dialog').textContent).toContain(
      'EDIT_DETAILS_FORM'
    );
    const firstName = wrapper
      .findComponent({ name: 'ContactsForm' })
      .find('input');
    await firstName.setValue('Pessoa de teste');
    await flushPromises();
    const submit = document.querySelector('dialog button[type="submit"]');
    expect(submit.disabled).toBe(false);
    submit.click();
    await flushPromises();
    expect(wrapper.emitted('create')?.[0]?.[0]).toMatchObject({
      name: 'Pessoa de teste',
    });
    if (draft?.additionalAttributes.city) {
      expect(
        wrapper.emitted('create')[0][0].additionalAttributes
      ).toMatchObject(draft.additionalAttributes);
    }
  });
});
