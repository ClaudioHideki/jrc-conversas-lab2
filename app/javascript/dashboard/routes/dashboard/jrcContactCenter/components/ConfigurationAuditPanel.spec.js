import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { webcrypto } from 'node:crypto';
import { Blob as NativeBlob } from 'node:buffer';
import { defineComponent, reactive, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import ConfigurationAuditPanel from './ConfigurationAuditPanel.vue';
import ConfigurationAuditPage from './ConfigurationAuditPage.vue';

const mocks = vi.hoisted(() => ({ route: null, replace: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => {
      if (key.endsWith('.ENTRY_LABEL'))
        return `${params.resource} #${params.id} · ${params.operation}`;
      if (key.endsWith('.PAGE_LABEL'))
        return `JRC_CONTACT_CENTER.ADMIN.PAGE ${params.page} / ${params.pages}`;
      return params?.id ? `${key}: ${params.id}` : key;
    },
  }),
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    configurationAudits: vi.fn(),
    configurationAudit: vi.fn(),
    exportConfigurationAudits: vi.fn(),
    administrativeList: vi.fn(),
  },
}));
const Dialog = defineComponent({
  emits: ['close'],
  setup(_props, { expose, emit }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
      close: () => {
        visible.value = false;
        emit('close');
      },
    });
    return { visible };
  },
  template:
    '<div v-if="visible" data-dialog><slot /><slot name="footer" /></div>',
});
const event = {
  id: 7,
  resource_type: 'queue',
  resource_id: 2,
  operation: 'update',
  created_at: '2026-11-17T12:00:00Z',
  actor_id: 4,
  actor_name: 'Authorized actor',
  correlation_id: 'SYNTHETIC correlation',
  result: 'recorded_locally',
  revision: 2,
  before: { name: 'Previous' },
  after: { name: 'Current' },
  scopes: {
    before: { account_id: '1', unit_id: '10' },
    after: { account_id: '1', unit_id: '10' },
  },
  omitted_fields: [],
};
const response = (items = [event], meta = {}) => ({
  data: {
    items,
    actors: [{ id: 4, name: 'Authorized actor' }],
    meta: { total: items.length, pages: 1, page: 1, ...meta },
    window: {
      from: '2026-10-19',
      to: '2026-11-17',
      timezone: 'America/Sao_Paulo',
    },
  },
});
const context = reports => ({
  capabilities: { reports, configuration_audit: true },
  units: [{ id: 10, name: 'Authorized unit' }],
});
const render = (reports = true) =>
  mount(ConfigurationAuditPanel, {
    props: { accountId: '1', context: context(reports) },
    global: { stubs: { Dialog } },
  });
enableAutoUnmount(afterEach);
afterEach(() => vi.unstubAllGlobals());
beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal('crypto', webcrypto);
  mocks.route = reactive({ query: { unrelated_filter: 'preserved' } });
  mocks.replace.mockImplementation(async ({ query }) => {
    mocks.route.query = query;
  });
  API.configurationAudits.mockResolvedValue(response());
  API.configurationAudit.mockResolvedValue({
    data: { item: event, timezone: 'America/Sao_Paulo' },
  });
});

describe('scoped administrative audit interface', () => {
  it.each([
    ['audio_folder', 'JRC_CONTACT_CENTER.AUDIO_FOLDERS.TITLE'],
    ['team_source', 'JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.TEAM_SOURCE'],
  ])(
    'filters native %s records using its localized resource label',
    async (resource, label) => {
      const wrapper = render();
      await flushPromises();
      const filter = wrapper
        .findAll('select')
        .find(select => select.find(`option[value="${resource}"]`).exists());
      await filter.setValue(resource);
      await wrapper.find('form').trigger('submit');
      await flushPromises();
      expect(API.configurationAudits).toHaveBeenLastCalledWith(
        '1',
        expect.objectContaining({ resource_type: resource })
      );
      expect(filter.text()).toContain(label);
      expect(mocks.route.query.audit_config_resource_type).toBe(resource);
    }
  );

  it('filters native routing history without treating it as provider publication', async () => {
    const wrapper = render();
    await flushPromises();
    const filter = wrapper
      .findAll('select')
      .find(select => select.find('option[value="routing_rule"]').exists());
    await filter.setValue('routing_rule');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(API.configurationAudits).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ resource_type: 'routing_rule' })
    );
    expect(mocks.route.query.audit_config_resource_type).toBe('routing_rule');
    expect(filter.text()).toContain(
      'JRC_CONTACT_CENTER.ROUTING_DRAFTS.RESOURCE'
    );
  });

  it('closes read-only details through an explicit footer action without a form submit', async () => {
    const wrapper = render();
    await flushPromises();
    await wrapper.get('[data-audit-detail]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-dialog]').exists()).toBe(true);
    await wrapper.get('[data-dialog] button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-dialog]').exists()).toBe(false);
  });

  it('loads the authorized page with native timezone and bounded pagination', async () => {
    const wrapper = render();
    await flushPromises();
    expect(API.configurationAudits).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({ page: '1', per_page: 20 })
    );
    expect(wrapper.findAll('[data-audit-row]')).toHaveLength(1);
    expect(wrapper.text()).toContain('09:00');
    expect(wrapper.find('input[type=date]').element.value).toBe('2026-10-19');
    expect(wrapper.find('[data-audit-export]').exists()).toBe(true);
  });

  it('keeps unrelated navigation filters while applying and clearing audit criteria', async () => {
    const wrapper = render();
    await flushPromises();
    await wrapper.find('input[type=number]').setValue('2');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(mocks.route.query).toMatchObject({
      audit_config_resource_id: '2',
      unrelated_filter: 'preserved',
    });
    const clear = wrapper
      .findAll('button')
      .find(button => button.text() === 'JRC_CONTACT_CENTER.ADMIN.CLEAR');
    await clear.trigger('click');
    await flushPromises();
    expect(mocks.route.query).toEqual({ unrelated_filter: 'preserved' });
  });

  it('changes pages through the URL and requests the selected page', async () => {
    API.configurationAudits.mockResolvedValue(
      response([event], { total: 21, pages: 2 })
    );
    const wrapper = render();
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'JRC_CONTACT_CENTER.ADMIN.NEXT')
      .trigger('click');
    await flushPromises();
    expect(mocks.route.query.audit_config_page).toBe('2');
    expect(API.configurationAudits).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ page: '2' })
    );
  });

  it('shows query errors instead of presenting an empty successful list', async () => {
    API.configurationAudits.mockRejectedValue({
      response: { status: 422, data: { error: 'invalid_audit_dates' } },
    });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[data-audit-list-error]').text()).toContain(
      'DATES_ERROR'
    );
    expect(wrapper.find('[data-audit-preview]').exists()).toBe(false);
    expect(wrapper.findAll('[data-audit-row]')).toHaveLength(0);
  });

  it('loads full details and shows scopes and the sanitized before/after', async () => {
    const wrapper = render();
    await flushPromises();
    await wrapper.get('[data-audit-detail]').trigger('click');
    await flushPromises();
    expect(API.configurationAudit).toHaveBeenCalledWith('1', 7);
    expect(wrapper.get('[data-dialog]').text()).toContain('Previous');
    expect(wrapper.get('[data-dialog]').text()).toContain('Current');
    expect(wrapper.get('[data-dialog] [data-audit-scopes]').text()).toContain(
      '#10'
    );
  });

  it('keeps a denied detail visibly denied with no previous detail content', async () => {
    API.configurationAudit.mockRejectedValue({ response: { status: 404 } });
    const wrapper = render();
    await flushPromises();
    await wrapper.get('[data-audit-detail]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-dialog] [role=alert]').text()).toContain(
      'DENIED'
    );
    expect(wrapper.find('[data-dialog] [data-audit-details]').exists()).toBe(
      false
    );
  });

  it('uses the complete resource history without carrying unrelated date or actor restrictions', async () => {
    const wrapper = render();
    await flushPromises();
    await wrapper.get('[data-audit-row] button').trigger('click');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(
        button =>
          button.text() === 'JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.HISTORY'
      )
      .trigger('click');
    await flushPromises();
    expect(mocks.route.query).toMatchObject({
      audit_config_history: 'true',
      audit_config_resource_type: 'queue',
      audit_config_resource_id: '2',
    });
    expect(mocks.route.query.audit_config_from).toBeUndefined();
    expect(mocks.route.query.audit_config_actor_id).toBeUndefined();
  });

  it('discards a late list and its actor names after an account change', async () => {
    let finish;
    API.configurationAudits.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = render();
    await wrapper.setProps({ accountId: '2' });
    await flushPromises();
    finish(response([{ ...event, actor_name: 'PRIVATE OLD ACCOUNT' }]));
    await flushPromises();
    expect(wrapper.text()).not.toContain('PRIVATE OLD ACCOUNT');
    expect(API.configurationAudits).toHaveBeenLastCalledWith(
      '2',
      expect.any(Object)
    );
  });

  it('does not offer export without the separate native reports capability', async () => {
    const wrapper = render(false);
    await flushPromises();
    expect(wrapper.find('[data-audit-export]').exists()).toBe(false);
    expect(API.exportConfigurationAudits).not.toHaveBeenCalled();
  });

  it('rejects an export whose content hash does not match the response', async () => {
    API.exportConfigurationAudits.mockResolvedValue({
      data: { arrayBuffer: async () => new Uint8Array([1, 2, 3]).buffer },
      headers: { 'x-content-sha256': 'not-the-hash' },
    });
    const wrapper = render();
    await flushPromises();
    await wrapper.get('[data-audit-export]').trigger('click');
    await flushPromises();
    await vi.waitFor(() => {
      expect(wrapper.get('[data-audit-export-error]').text()).toContain(
        'EXPORT_INTEGRITY'
      );
    });
  });

  it('keeps the native audit flag closed without activating it or fetching records', async () => {
    mocks.route.query.audit_source = 'configuration';
    const wrapper = mount(ConfigurationAuditPage, {
      props: {
        accountId: '1',
        context: { capabilities: { audit: true, configuration_audit: false } },
      },
    });
    await flushPromises();
    expect(wrapper.get('[role=status]').text()).toContain('NOT_ENABLED');
    expect(API.configurationAudits).not.toHaveBeenCalled();
    expect(wrapper.find('[data-configuration-audit]').exists()).toBe(false);
  });
});

describe('native audit request references without exposing error payloads', () => {
  const id = '11111111-1111-4111-8111-111111111111';
  it('shows the native opaque query request ID with the translated error and no private database payload', async () => {
    API.configurationAudits.mockRejectedValueOnce({
      response: {
        status: 503,
        headers: { 'x-request-id': id },
        data: { error: 'SYNTHETIC private SQL diagnostic' },
      },
    });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[data-audit-list-error]').text()).toContain(id);
    expect(wrapper.text()).not.toContain('SYNTHETIC private SQL diagnostic');
    expect(wrapper.findAll('[data-audit-row]')).toHaveLength(0);
    expect(wrapper.find('[data-audit-preview]').exists()).toBe(false);
  });
  it('does not display an arbitrary non-UUID request header', async () => {
    API.configurationAudits.mockRejectedValueOnce({
      response: {
        status: 503,
        headers: { 'x-request-id': 'SYNTHETIC invalid <img src=x>' },
      },
    });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[data-audit-list-error]').text()).not.toContain(
      'SYNTHETIC invalid'
    );
    expect(wrapper.find('img').exists()).toBe(false);
  });
  it('keeps an offline query visibly failed without fabricating a server reference', async () => {
    API.configurationAudits.mockRejectedValueOnce(
      new Error('SYNTHETIC network unavailable')
    );
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[data-audit-list-error]').text()).toContain(
      'COMMON.ERROR'
    );
    expect(wrapper.text()).not.toContain('REQUEST_REFERENCE');
    expect(wrapper.find('[data-audit-preview]').exists()).toBe(false);
  });
  it('preserves denied details as denied and shows only their own native request identifier', async () => {
    API.configurationAudit.mockRejectedValueOnce({
      response: { status: 403, headers: { 'x-request-id': id } },
    });
    const wrapper = render();
    await flushPromises();
    await wrapper.get('[data-audit-detail]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-dialog] [role=alert]').text()).toContain(
      'DENIED'
    );
    expect(wrapper.get('[data-dialog] [role=alert]').text()).toContain(id);
    expect(wrapper.get('[data-dialog]').text()).not.toContain('Previous');
  });
  it('preserves a Blob export failure and its native identifier instead of producing a download', async () => {
    vi.stubGlobal('Blob', NativeBlob);
    API.exportConfigurationAudits.mockRejectedValueOnce({
      response: {
        status: 422,
        headers: { 'x-request-id': id },
        data: new Blob([
          JSON.stringify({ error: 'audit_export_limit_exceeded' }),
        ]),
      },
    });
    const wrapper = render();
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(
        button =>
          button.text() === 'JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.EXPORT'
      )
      .trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-audit-export-error]').text()).toContain(id);
    expect(wrapper.get('[data-audit-export-error]').text()).toContain(
      'EXPORT_LIMIT'
    );
  });
  it('clears the old request identifier after an explicit successful query', async () => {
    API.configurationAudits.mockRejectedValueOnce({
      response: { status: 503, headers: { 'x-request-id': id } },
    });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[data-audit-list-error]').text()).toContain(id);
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(wrapper.find('[data-audit-list-error]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain(id);
    expect(wrapper.findAll('[data-audit-row]')).toHaveLength(1);
  });
});

describe('native administrative audit table from the Word reference', () => {
  it('presents semantic columns, the authenticated actor, native date and local result while preserving row preview and popup', async () => {
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[data-audit-table]').element.tagName).toBe('TABLE');
    expect(wrapper.findAll('thead th')).toHaveLength(6);
    const row = wrapper.get('[data-audit-row]');
    expect(row.element.tagName).toBe('TR');
    expect(row.findAll('td')).toHaveLength(6);
    expect(row.get('time').attributes('datetime')).toBe(event.created_at);
    expect(row.text()).toContain('Authorized actor');
    expect(row.get('[data-audit-local-result]').text()).toContain(
      'RECORDED_LOCALLY'
    );
    await row.get('button').trigger('click');
    await flushPromises();
    expect(API.configurationAudit).toHaveBeenLastCalledWith('1', event.id);
    expect(
      wrapper.find('[data-audit-preview] [data-audit-details]').exists()
    ).toBe(true);
    await row.get('[data-audit-detail]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-dialog]').text()).toContain('Previous');
  });

  it('does not turn an unknown result into a local or PABX confirmation', async () => {
    API.configurationAudits.mockResolvedValue(
      response([{ ...event, result: 'SYNTHETIC unknown' }])
    );
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[data-audit-local-result]').text()).toContain(
      'NO_CONFIRMATION'
    );
    expect(wrapper.get('[data-audit-local-result]').text()).not.toContain(
      'RECORDED_LOCALLY'
    );
    expect(wrapper.text()).not.toContain('SYNTHETIC unknown');
  });
});
