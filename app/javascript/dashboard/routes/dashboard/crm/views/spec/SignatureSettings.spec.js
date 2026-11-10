import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import SignatureSettings from '../backoffice/SignatureSettings.vue';

const mocks = vi.hoisted(() => ({
  showForAccount: vi.fn(),
  saveForAccount: vi.fn(),
  checkForAccount: vi.fn(),
  route: null,
  getters: null,
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('dashboard/api/crm/commercialCycle', () => ({
  signatureIntegrationAPI: mocks,
}));
const status = (overrides = {}) => ({
  data: {
    configured: true,
    can_manage: true,
    revision: 1,
    enabled: true,
    authorization_checked: false,
    connect_checked: false,
    delivery_ready: false,
    details: {
      environment: 'demo',
      integration_key: 'synthetic-integration-id',
      impersonated_user_id: 'synthetic-user-id',
      external_account_id: 'synthetic-account-id',
      enabled: true,
    },
    ...overrides,
  },
});
const button = (wrapper, text) =>
  wrapper.findAll('button').find(node => node.text().includes(text));

describe('DocuSign connection settings', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.route = reactive({ params: { accountId: '1' } });
    mocks.getters = reactive({ getCurrentUser: { id: 7 } });
    mocks.showForAccount.mockResolvedValue(status());
  });

  it('does not treat configured credentials as verified authorization or a received Connect notification', async () => {
    const wrapper = mount(SignatureSettings);
    await flushPromises();
    await button(wrapper, 'Verificações').trigger('click');
    expect(wrapper.findAll('dd').map(node => node.text())).toEqual([
      'Registrada',
      'Ainda não verificado',
      'Ainda não verificado',
    ]);
    expect(wrapper.text()).toContain('endereço HTTPS público');
    expect(mocks.checkForAccount).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('saves explicitly to the captured account and clears private credentials after success', async () => {
    mocks.saveForAccount.mockResolvedValue(status({ revision: 2 }));
    const wrapper = mount(SignatureSettings);
    await flushPromises();
    await wrapper.findAll('textarea')[0].setValue('SYNTHETIC PRIVATE KEY');
    await wrapper
      .findAll('textarea')[1]
      .setValue('synthetic-key-1\nsynthetic-key-2');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(mocks.saveForAccount).toHaveBeenCalledWith('1', {
      revision: 1,
      integration: expect.objectContaining({
        private_key: 'SYNTHETIC PRIVATE KEY',
        connect_hmac_keys: ['synthetic-key-1', 'synthetic-key-2'],
      }),
    });
    expect(wrapper.findAll('textarea').map(node => node.element.value)).toEqual(
      ['', '']
    );
    expect(wrapper.find('[role="status"]').text()).toContain(
      'Configuração salva'
    );
    wrapper.unmount();
  });

  it('discards an old account response after changing account', async () => {
    let finish;
    mocks.showForAccount.mockReturnValueOnce(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    mocks.showForAccount.mockResolvedValueOnce(
      status({ can_manage: false, details: null })
    );
    const wrapper = mount(SignatureSettings);
    mocks.route.params.accountId = '2';
    await flushPromises();
    finish(status({ details: { external_account_id: 'PRIVATE OLD ACCOUNT' } }));
    await flushPromises();
    expect(wrapper.findAll('input')).toHaveLength(0);
    expect(wrapper.html()).not.toContain('PRIVATE OLD ACCOUNT');
    expect(mocks.showForAccount.mock.lastCall[0]).toBe('2');
    wrapper.unmount();
  });

  it('clears an edited secret and ignores an in-flight save after a user switch', async () => {
    let finish;
    mocks.saveForAccount.mockReturnValueOnce(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    const wrapper = mount(SignatureSettings);
    await flushPromises();
    await wrapper.findAll('textarea')[0].setValue('SYNTHETIC PRIVATE KEY');
    await wrapper.find('form').trigger('submit');
    mocks.getters.getCurrentUser.id = 8;
    await flushPromises();
    finish(status({ details: { external_account_id: 'PRIVATE OLD USER' } }));
    await flushPromises();
    expect(wrapper.findAll('textarea').map(node => node.element.value)).toEqual(
      ['', '']
    );
    expect(wrapper.html()).not.toContain('PRIVATE OLD USER');
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('reports missing consent without showing successful authorization', async () => {
    mocks.checkForAccount.mockRejectedValue({
      response: { status: 422, data: { code: 'CONSENT_REQUIRED' } },
    });
    const wrapper = mount(SignatureSettings);
    await flushPromises();
    await button(wrapper, 'Verificações').trigger('click');
    await button(wrapper, 'Verificar autorização').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'conceder consentimento'
    );
    expect(wrapper.findAll('dd')[1].text()).toBe('Ainda não verificado');
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('clears both credentials and management details when permission is revoked during save', async () => {
    mocks.saveForAccount.mockRejectedValue({ response: { status: 403 } });
    const wrapper = mount(SignatureSettings);
    await flushPromises();
    await wrapper.findAll('textarea')[0].setValue('SYNTHETIC PRIVATE KEY');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(wrapper.find('form').exists()).toBe(false);
    expect(wrapper.find('[role="alert"]').text()).toContain('acesso');
    wrapper.unmount();
  });
});
