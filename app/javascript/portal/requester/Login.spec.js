import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import Login from './Login.vue';
import { login, request } from './client';
import en from './en.json';

vi.mock('./client', () => ({
  login: vi.fn(),
  request: vi.fn(),
  errorKey: () => 'PORTAL.DENIED',
}));

const buildWrapper = (samlEnabled = false) =>
  mount(Login, {
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
      provide: { portalSamlEnabled: samlEnabled },
    },
  });

describe('Requester portal native login', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it.each([
    ['123456', { otp_code: '123456' }],
    ['native-backup-code', { backup_code: 'native-backup-code' }],
  ])(
    'uses the existing native MFA challenge for %s',
    async (verification, answer) => {
      login.mockResolvedValueOnce({
        mfa_required: true,
        mfa_token: 'native-challenge',
      });
      login.mockRejectedValueOnce(new Error('Native verification refused'));
      const wrapper = buildWrapper();
      await wrapper
        .get('input[type="email"]')
        .setValue('requester@example.test');
      await wrapper.get('input[type="password"]').setValue('native-password');
      await wrapper.get('form').trigger('submit');
      await flushPromises();
      expect(login).toHaveBeenNthCalledWith(1, {
        email: 'requester@example.test',
        password: 'native-password',
      });
      expect(wrapper.find('input[type="password"]').exists()).toBe(false);
      await wrapper
        .get('input[autocomplete="one-time-code"]')
        .setValue(verification);
      await wrapper.get('form').trigger('submit');
      await flushPromises();
      expect(login).toHaveBeenNthCalledWith(2, {
        mfa_token: 'native-challenge',
        ...answer,
      });
      expect(wrapper.get('[role="alert"]').text()).toBe(en.PORTAL.DENIED);
    }
  );

  it('uses native password recovery with the entered identity', async () => {
    request.mockResolvedValue({});
    const wrapper = buildWrapper();
    await wrapper.get('input[type="email"]').setValue('requester@example.test');
    await wrapper.get('button[type="button"]').trigger('click');
    await flushPromises();
    expect(request).toHaveBeenCalledWith('/auth/password', {
      method: 'POST',
      body: { email: 'requester@example.test' },
    });
    expect(wrapper.get('[role="alert"]').text()).toBe(en.PORTAL.RECOVERY_SENT);
  });

  it('only offers the existing Enterprise SSO screen when explicitly available', () => {
    expect(buildWrapper().find('a[href="/app/login/sso"]').exists()).toBe(
      false
    );
    expect(buildWrapper(true).get('a[href="/app/login/sso"]').text()).toBe(
      en.PORTAL.SSO
    );
  });
});
