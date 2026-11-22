import { afterEach, describe, expect, it } from 'vitest';
import { enableAutoUnmount, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/en/jrcApprovals.json';
import ApprovalInbox from '../ApprovalInbox.vue';

enableAutoUnmount(afterEach);
const render = (moduleKey, localMessages = {}) =>
  mount(ApprovalInbox, {
    props: {
      rows: [
        {
          id: 7,
          module_key: moduleKey,
          policy_name: 'SYNTHETIC policy',
          requester_name: 'SYNTHETIC operator',
          state: 'pending',
          created_at: '2026-11-22T12:00:00Z',
        },
      ],
    },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          fallbackLocale: 'en',
          messages: { en: messages, pt_BR: localMessages },
        }),
      ],
      stubs: { Icon: true },
    },
  });

describe('native approval module labels with actual locale fallback', () => {
  it('identifies Call Center pauses even when the current locale relies on the source fallback', () => {
    const wrapper = render('contact_center');
    expect(wrapper.text()).toContain('Call Center');
    expect(wrapper.text()).not.toContain(
      messages.JRC_APPROVALS.workspace.modules.other
    );
  });

  it('preserves the existing CRM label through the same source fallback', () => {
    const wrapper = render('crm');
    expect(wrapper.text()).toContain(
      messages.JRC_APPROVALS.workspace.modules.crm
    );
    expect(wrapper.text()).not.toContain(
      messages.JRC_APPROVALS.workspace.modules.other
    );
  });

  it('keeps an unknown untranslated source generic instead of presenting its technical identifier', () => {
    const wrapper = render('synthetic_unknown_module');
    expect(wrapper.text()).toContain(
      messages.JRC_APPROVALS.workspace.modules.other
    );
    expect(wrapper.text()).not.toContain('synthetic_unknown_module');
  });

  it('preserves an existing custom translated module label', () => {
    const wrapper = render('synthetic_custom_module', {
      JRC_APPROVALS: {
        workspace: {
          modules: { synthetic_custom_module: 'SYNTHETIC custom label' },
        },
      },
    });
    expect(wrapper.text()).toContain('SYNTHETIC custom label');
    expect(wrapper.text()).not.toContain(
      messages.JRC_APPROVALS.workspace.modules.other
    );
  });
});
