import { flushPromises, mount, shallowMount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import calls from 'dashboard/i18n/locale/pt_BR/calls.json';
import english from 'dashboard/i18n/locale/en/calls.json';
import TelephonyIntegrationAPI from 'dashboard/api/telephonyIntegration';
import PabxSettingsPanel from './PabxSettingsPanel.vue';
import SipSettingsPage from './SipSettingsPage.vue';

vi.mock('dashboard/api/telephonyIntegration', () => ({
  default: {
    get: vi.fn(),
    save: vi.fn(),
    testConnection: vi.fn(),
    synchronize: vi.fn(),
  },
}));
vi.mock('dashboard/api/agents', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/sipCredentials', () => ({ default: { get: vi.fn() } }));

describe('PABX configuration and extension diagnosis', () => {
  let payload;
  beforeEach(() => {
    payload = { settings: {}, configured: false, sync: {} };
    TelephonyIntegrationAPI.get.mockImplementation(async () => ({
      data: payload,
    }));
  });
  const plugins = () => [
    createI18n({
      legacy: false,
      locale: 'pt_BR',
      fallbackLocale: 'en',
      messages: { pt_BR: calls, en: english },
    }),
  ];

  it('loads configuration with both operational switches OFF and never starts an external operation automatically', async () => {
    const wrapper = mount(PabxSettingsPanel, {
      global: { plugins: plugins() },
    });
    await flushPromises();
    expect(wrapper.vm.form.enabled).toBe(false);
    expect(wrapper.vm.form.sync_enabled).toBe(false);
    expect(TelephonyIntegrationAPI.get).toHaveBeenCalledOnce();
    expect(TelephonyIntegrationAPI.testConnection).not.toHaveBeenCalled();
    expect(TelephonyIntegrationAPI.synchronize).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('displays expected 8 versus returned 12 clearly without claiming overall success or changing the saved tenant', async () => {
    payload = {
      settings: { expected_tenant: '8', base_url: 'https://pbx.example.test' },
      configured: true,
      sync: {},
    };
    TelephonyIntegrationAPI.testConnection.mockResolvedValue({
      data: {
        expected_tenant: '8',
        returned_accountcode: '12',
        api: 'connected',
        authentication: 'ok',
        tenant_compatible: false,
        overall: 'blocked_scope',
        error: 'TENANT_MISMATCH',
      },
    });
    const wrapper = mount(PabxSettingsPanel, {
      global: { plugins: plugins() },
    });
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === calls.SOFTPHONE.PABX.TEST)
      .trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(calls.SOFTPHONE.PABX.CHECK_BLOCKED);
    expect(wrapper.text()).toContain('8');
    expect(wrapper.text()).toContain('12');
    expect(wrapper.text()).not.toContain(calls.SOFTPHONE.PABX.CHECK_PASSED);
    expect(wrapper.vm.form.expected_tenant).toBe('8');
    expect(TelephonyIntegrationAPI.synchronize).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('shows the real technical status and native collaborator returned by the diagnosis', async () => {
    payload.sync.diagnostic = {
      technical_status: 'BUSY',
      extension: '1410',
      technical_extension: '81410',
      overall: 'checks_passed',
      collaborators: [{ user_id: 27, name: 'Synthetic Collaborator' }],
    };
    const wrapper = mount(PabxSettingsPanel, {
      global: { plugins: plugins() },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('BUSY');
    expect(wrapper.text()).toContain('Synthetic Collaborator');
    wrapper.unmount();
  });

  it('requires saving modified configuration before diagnostics and clears credentials after saving', async () => {
    payload.configured = true;
    TelephonyIntegrationAPI.save.mockResolvedValue({ data: payload });
    const wrapper = mount(PabxSettingsPanel, {
      global: { plugins: plugins() },
    });
    await flushPromises();
    wrapper.vm.password = 'synthetic-new-password';
    await wrapper.vm.$nextTick();
    expect(
      wrapper
        .findAll('button')
        .find(button => button.text() === calls.SOFTPHONE.PABX.TEST)
        .attributes('disabled')
    ).toBeDefined();
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(wrapper.vm.password).toBe('');
    expect(wrapper.text()).not.toContain('synthetic-new-password');
    expect(TelephonyIntegrationAPI.testConnection).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('resets omitted fields instead of keeping stale configuration after a save', async () => {
    payload.settings = {
      base_url: 'https://pbx.example.test',
      expected_tenant: '8',
    };
    TelephonyIntegrationAPI.save.mockResolvedValue({
      data: { settings: {}, configured: false, sync: {} },
    });
    const wrapper = mount(PabxSettingsPanel, {
      global: { plugins: plugins() },
    });
    await flushPromises();
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(wrapper.vm.form.base_url).toBe('');
    expect(wrapper.vm.form.expected_tenant).toBe('');
    wrapper.unmount();
  });

  it('clears an older successful diagnosis when a new diagnostic request fails', async () => {
    payload = {
      settings: {},
      configured: true,
      sync: { diagnostic: { overall: 'checks_passed' } },
    };
    TelephonyIntegrationAPI.testConnection.mockRejectedValue(
      new Error('private provider detail')
    );
    const wrapper = mount(PabxSettingsPanel, {
      global: { plugins: plugins() },
    });
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === calls.SOFTPHONE.PABX.TEST)
      .trigger('click');
    await flushPromises();
    expect(wrapper.vm.diagnostic).toBe(null);
    expect(wrapper.text()).not.toContain(calls.SOFTPHONE.PABX.CHECK_PASSED);
    expect(wrapper.text()).not.toContain('private provider detail');
    wrapper.unmount();
  });

  it('warns explicitly when HTTP is selected for LAB', async () => {
    payload.settings = {
      base_url: 'http://pbx.example.test',
      allow_http_lab: true,
    };
    const wrapper = mount(PabxSettingsPanel, {
      global: { plugins: plugins() },
    });
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toContain(
      calls.SOFTPHONE.PABX.HTTP_WARNING
    );
    wrapper.unmount();
  });

  it('does not mount the administrative PABX panel for an ordinary user', async () => {
    const store = createStore({
      getters: { getCurrentUser: () => ({ id: 7, type: 'User' }) },
    });
    const wrapper = shallowMount(SipSettingsPage, {
      global: { plugins: [...plugins(), store] },
    });
    await flushPromises();
    expect(wrapper.findComponent(PabxSettingsPanel).exists()).toBe(false);
    expect(TelephonyIntegrationAPI.get).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('retains the complete native presentation for callers that do not opt into tabs', async () => {
    const wrapper = mount(PabxSettingsPanel, {
      global: { plugins: plugins() },
    });
    await flushPromises();
    expect(wrapper.find('[role="tablist"]').exists()).toBe(false);
    expect(wrapper.get('[data-pabx-panel="general"]').isVisible()).toBe(true);
    expect(wrapper.get('[data-pabx-panel="sync"]').isVisible()).toBe(true);
    expect(wrapper.get('[data-pabx-panel="diagnostic"]').isVisible()).toBe(
      true
    );
    wrapper.unmount();
  });

  it('keeps the same draft and submits all reviewed sections together across tab changes', async () => {
    TelephonyIntegrationAPI.save.mockImplementation(async request => ({
      data: { settings: request.settings, configured: true, sync: {} },
    }));
    const wrapper = mount(PabxSettingsPanel, {
      props: { tabbed: true },
      global: { plugins: plugins() },
    });
    await flushPromises();
    await wrapper
      .get('[data-pabx-panel="general"] input[type="url"]')
      .setValue('https://synthetic.example.test');
    wrapper.vm.password = 'SYNTHETIC review';
    await wrapper.get('[data-pabx-tab="sync"]').trigger('click');
    await wrapper.get('textarea').setValue('{"duration":"seconds"}');
    await wrapper.get('[data-pabx-tab="diagnostic"]').trigger('click');
    expect(wrapper.get('[data-pabx-panel="general"]').isVisible()).toBe(false);
    expect(TelephonyIntegrationAPI.get).toHaveBeenCalledOnce();
    expect(TelephonyIntegrationAPI.testConnection).not.toHaveBeenCalled();
    expect(TelephonyIntegrationAPI.synchronize).not.toHaveBeenCalled();
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(TelephonyIntegrationAPI.save).toHaveBeenCalledOnce();
    expect(TelephonyIntegrationAPI.save).toHaveBeenCalledWith(
      expect.objectContaining({
        settings: expect.objectContaining({
          base_url: 'https://synthetic.example.test',
          cdr_fields: { duration: 'seconds' },
        }),
        api_password: 'SYNTHETIC review',
      })
    );
    expect(wrapper.vm.password).toBe('');
    wrapper.unmount();
  });

  it('never sends blank settings after a failed initial load and allows an explicit safe retry', async () => {
    TelephonyIntegrationAPI.get.mockRejectedValueOnce(
      new Error('sensitive provider detail')
    );
    const wrapper = mount(PabxSettingsPanel, {
      props: { tabbed: true },
      global: { plugins: plugins() },
    });
    await flushPromises();
    expect(wrapper.get('fieldset').attributes('disabled')).toBeDefined();
    await wrapper.find('form').trigger('submit');
    expect(TelephonyIntegrationAPI.save).not.toHaveBeenCalled();
    expect(wrapper.text()).not.toContain('sensitive provider detail');
    await wrapper
      .findAll('button')
      .find(button => button.text() === english.SOFTPHONE.PABX.RELOAD)
      .trigger('click');
    await flushPromises();
    expect(wrapper.get('fieldset').attributes('disabled')).toBeUndefined();
    wrapper.unmount();
  });

  it('preserves the draft when invalid JSON prevents a save', async () => {
    const wrapper = mount(PabxSettingsPanel, {
      props: { tabbed: true },
      global: { plugins: plugins() },
    });
    await flushPromises();
    await wrapper.get('[data-pabx-tab="sync"]').trigger('click');
    await wrapper.get('textarea').setValue('{ invalid');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(TelephonyIntegrationAPI.save).not.toHaveBeenCalled();
    expect(wrapper.get('textarea').element.value).toBe('{ invalid');
    expect(wrapper.text()).toContain(calls.SOFTPHONE.PABX.FAILED);
    wrapper.unmount();
  });

  it('preserves credentials and reviewed fields after a failed save without showing private errors', async () => {
    TelephonyIntegrationAPI.save.mockRejectedValueOnce(
      new Error('private backend detail')
    );
    const wrapper = mount(PabxSettingsPanel, {
      props: { tabbed: true },
      global: { plugins: plugins() },
    });
    await flushPromises();
    wrapper.vm.password = 'SYNTHETIC unsaved';
    await wrapper
      .get('[data-pabx-panel="general"] input[type="url"]')
      .setValue('https://synthetic.example.test');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(wrapper.vm.password).toBe('SYNTHETIC unsaved');
    expect(wrapper.vm.form.base_url).toBe('https://synthetic.example.test');
    expect(wrapper.text()).not.toContain('private backend detail');
    expect(wrapper.text()).not.toContain('SYNTHETIC unsaved');
    wrapper.unmount();
  });

  it('blocks duplicate submissions and tab actions while a save is pending', async () => {
    let complete;
    TelephonyIntegrationAPI.save.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          complete = resolve;
        })
    );
    const wrapper = mount(PabxSettingsPanel, {
      props: { tabbed: true },
      global: { plugins: plugins() },
    });
    await flushPromises();
    await wrapper.find('form').trigger('submit');
    await wrapper.find('form').trigger('submit');
    expect(TelephonyIntegrationAPI.save).toHaveBeenCalledOnce();
    expect(
      wrapper.get('[data-pabx-tab="sync"]').attributes('disabled')
    ).toBeDefined();
    complete({ data: payload });
    await flushPromises();
    expect(
      wrapper.get('[data-pabx-tab="sync"]').attributes('disabled')
    ).toBeUndefined();
    wrapper.unmount();
  });

  it('changes focus and selection with the keyboard without issuing API commands', async () => {
    const wrapper = mount(PabxSettingsPanel, {
      attachTo: document.body,
      props: { tabbed: true },
      global: { plugins: plugins() },
    });
    await flushPromises();
    await wrapper
      .get('[data-pabx-tab="general"]')
      .trigger('keydown', { key: 'End' });
    expect(
      wrapper.get('[data-pabx-tab="diagnostic"]').attributes('aria-selected')
    ).toBe('true');
    expect(document.activeElement).toBe(
      wrapper.get('[data-pabx-tab="diagnostic"]').element
    );
    await wrapper
      .get('[data-pabx-tab="diagnostic"]')
      .trigger('keydown', { key: 'ArrowLeft' });
    expect(
      wrapper.get('[data-pabx-tab="sync"]').attributes('aria-selected')
    ).toBe('true');
    expect(TelephonyIntegrationAPI.save).not.toHaveBeenCalled();
    expect(TelephonyIntegrationAPI.testConnection).not.toHaveBeenCalled();
    expect(TelephonyIntegrationAPI.synchronize).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('discards only after explicit reload and retains the draft if that read fails', async () => {
    const wrapper = mount(PabxSettingsPanel, {
      props: { tabbed: true },
      global: { plugins: plugins() },
    });
    await flushPromises();
    await wrapper
      .get('[data-pabx-panel="general"] input[type="url"]')
      .setValue('https://synthetic.example.test');
    const restore = wrapper
      .findAll('button')
      .find(button => button.text() === english.SOFTPHONE.PABX.RESTORE);
    TelephonyIntegrationAPI.get.mockRejectedValueOnce(
      new Error('temporary read failure')
    );
    await restore.trigger('click');
    await flushPromises();
    expect(wrapper.vm.form.base_url).toBe('https://synthetic.example.test');
    await restore.trigger('click');
    await flushPromises();
    expect(wrapper.vm.form.base_url).toBe('');
    expect(TelephonyIntegrationAPI.save).not.toHaveBeenCalled();
    expect(TelephonyIntegrationAPI.synchronize).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
