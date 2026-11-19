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
  it('uses routing-specific headings only for the native routing resource', async () => {
    const wrapper = render({
      resource_type: 'routing_rule',
      before: { kind: 'ddd' },
      after: { kind: 'service' },
    });
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.ROUTING_DRAFTS.KIND');
    expect(wrapper.text()).not.toContain('JRC_CONTACT_CENTER.ADMIN.KIND');
    await wrapper.setProps({
      record: {
        id: 8,
        resource_type: 'unit',
        before: { kind: 'sac' },
        after: { kind: 'cobranca' },
      },
    });
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.ADMIN.KIND');
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.ROUTING_DRAFTS.KIND'
    );
    wrapper.unmount();
  });

  it('renders sanitized routing history using native target and state labels', () => {
    const wrapper = render({
      before: { source_value: '11', kind: 'ddd', state: 'draft' },
      after: {
        source_value: '21',
        target_unit_id: 10,
        target_queue_id: 20,
        state: 'retired',
      },
      omitted_fields: ['conditions'],
    });
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.ROUTING_DRAFTS.SOURCE'
    );
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.ROUTING_DRAFTS.TARGET_UNIT'
    );
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.ROUTING_DRAFTS.TARGET_QUEUE'
    );
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.ROUTING_DRAFTS.DDD');
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.ROUTING_DRAFTS.RETIRED'
    );
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.OMITTED'
    );
    expect(wrapper.text()).not.toContain('undefined');
    wrapper.unmount();
  });

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
