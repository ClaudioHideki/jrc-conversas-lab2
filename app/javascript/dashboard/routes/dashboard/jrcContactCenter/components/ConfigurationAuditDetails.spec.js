import { describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import ConfigurationAuditDetails from './ConfigurationAuditDetails.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const render = (record = {}) =>
  mount(ConfigurationAuditDetails, {
    props: {
      date: '18/11/2026, 12:00',
      resourceLabel: 'SYNTHETIC ACW policy',
      operationLabel: 'SYNTHETIC update',
      record: {
        id: 7,
        resource_id: 1,
        revision: 2,
        actor_name: 'SYNTHETIC actor',
        correlation_id: 'SYNTHETIC correlation',
        before: { voice: 180, whatsapp: 180, voice_required: true },
        after: { voice: 120, whatsapp: 240, voice_required: false },
        scopes: { before: { account_id: '1' }, after: { account_id: '1' } },
        ...record,
      },
    },
  });

describe('native ACW audit detail', () => {
  it('renders channel seconds with translated field labels and preserves an explicit false', () => {
    const wrapper = render();
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.ACW_OPERATION.LIMIT_LABELS.voice'
    );
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.ACW_OPERATION.LIMIT_LABELS.whatsapp'
    );
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.ADMIN.VOICE_REQUIRED');
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.YES'
    );
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.NO'
    );
    expect(wrapper.text()).toContain('120');
    expect(wrapper.text()).toContain('240');
    wrapper.unmount();
  });

  it('does not replace a missing legacy value with a fabricated number', () => {
    const wrapper = render({
      before: { whatsapp: 180 },
      after: { voice: 120 },
      omitted_fields: ['voice'],
    });
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.OMITTED'
    );
    expect(wrapper.text()).toContain('—');
    expect(wrapper.text()).not.toContain('undefined');
    wrapper.unmount();
  });

  it('reacts to another native record rather than retaining the previous fields', async () => {
    const wrapper = render();
    await wrapper.setProps({
      record: {
        id: 8,
        resource_id: 2,
        before: { name: 'SYNTHETIC previous' },
        after: { name: 'SYNTHETIC new' },
      },
    });
    expect(wrapper.text()).toContain('SYNTHETIC new');
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.ADMIN.VOICE_REQUIRED'
    );
    wrapper.unmount();
  });
});
