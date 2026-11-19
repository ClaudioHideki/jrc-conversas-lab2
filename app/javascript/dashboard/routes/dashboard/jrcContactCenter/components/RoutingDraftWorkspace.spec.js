import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, reactive } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import RoutingDraftWorkspace from './RoutingDraftWorkspace.vue';

const mocks = vi.hoisted(() => ({ route: null, replace: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    routingRules: vi.fn(),
    configurationRecord: vi.fn(),
    saveRoutingRule: vi.fn(),
    ivrReference: vi.fn(),
  },
}));
const response = (name = 'SYNTHETIC local rule', meta = {}) => ({
  data: {
    items: [
      {
        id: 7,
        rule_key: name,
        kind: 'ddd',
        source_value: '11',
        state: 'draft',
        version: 1,
      },
    ],
    meta: { total: 1, pages: 1, page: 1, ...meta },
  },
});
const context = {
  capabilities: { configure: true, configuration_audit: true },
};
const Link = defineComponent({
  props: { to: { type: Object, required: true } },
  setup:
    (props, { slots }) =>
    () =>
      h('a', { href: props.to.name }, slots.default?.()),
});
const openDialog = vi.fn();
const closeDialog = vi.fn();
const DialogStub = {
  setup(_props, { expose }) {
    expose({ open: openDialog, close: closeDialog });
    return () => h('div');
  },
};
const render = () =>
  mount(RoutingDraftWorkspace, {
    props: { accountId: '1', context },
    global: { stubs: { Dialog: DialogStub, RouterLink: Link } },
  });
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ query: { unrelated: 'preserved' } });
  mocks.replace.mockImplementation(async ({ query }) => {
    mocks.route.query = query;
  });
  API.routingRules.mockResolvedValue(response());
});

describe('native routing draft workspace', () => {
  it('opens the exact native history without stale audit filters while preserving unrelated navigation', async () => {
    mocks.route.query = {
      unrelated: 'preserved',
      audit_config_page: '55',
      audit_config_operation: 'destroy',
      audit_source: 'old',
    };
    const wrapper = render();
    await flushPromises();
    expect(wrapper.getComponent(Link).props('to')).toEqual({
      name: 'jrc_contact_center_admin_section',
      params: { accountId: '1', section: 'audit' },
      query: {
        unrelated: 'preserved',
        audit_source: 'configuration',
        audit_config_resource_type: 'routing_rule',
        audit_config_resource_id: '7',
        audit_config_history: 'true',
      },
    });
  });

  it('loads only the bounded native list with actual totals and no impossible empty page count', async () => {
    const wrapper = render();
    await flushPromises();
    expect(API.routingRules).toHaveBeenCalledWith('1', {
      page: '1',
      per_page: 20,
      q: '',
      state: '',
      kind: '',
    });
    expect(wrapper.get('[data-routing-row]').text()).toContain(
      'SYNTHETIC local rule'
    );
    expect(wrapper.get('[data-routing-total]').text()).toContain('1');
    API.routingRules.mockResolvedValue({
      data: { items: [], meta: { total: 0, page: 1, pages: 0 } },
    });
    await wrapper.setProps({ accountId: '2' });
    await flushPromises();
    expect(wrapper.text()).not.toContain('1 de 0');
    expect(wrapper.get('[data-routing-next]').element.disabled).toBe(true);
    expect(wrapper.find('[data-routing-row]').exists()).toBe(false);
  });

  it('preserves unrelated URL criteria while applying filters, pagination and clearing', async () => {
    API.routingRules.mockResolvedValue(
      response('SYNTHETIC paged', { total: 21, pages: 2 })
    );
    const wrapper = render();
    await flushPromises();
    await wrapper.get('[data-routing-next]').trigger('click');
    await flushPromises();
    expect(API.routingRules).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ page: '2' })
    );
    await wrapper.get('[data-routing-search]').setValue('SYNTHETIC exact');
    await wrapper.get('[data-routing-filter-kind]').setValue('ddd');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.route.query).toMatchObject({
      unrelated: 'preserved',
      routing_page: '1',
      routing_q: 'SYNTHETIC exact',
      routing_kind: 'ddd',
    });
    await wrapper.get('[data-routing-clear]').trigger('click');
    await flushPromises();
    expect(API.routingRules).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ q: '', kind: '', state: '', page: '1' })
    );
    expect(mocks.route.query.unrelated).toBe('preserved');
  });

  it('discards a private old-account list even when it arrives after the next account', async () => {
    let finish;
    API.routingRules.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = render();
    await wrapper.setProps({ accountId: '2' });
    await flushPromises();
    finish(response('PRIVATE OLD ACCOUNT'));
    await flushPromises();
    expect(wrapper.text()).not.toContain('PRIVATE OLD ACCOUNT');
    expect(wrapper.text()).toContain('SYNTHETIC local rule');
    expect(API.routingRules).toHaveBeenLastCalledWith('2', expect.any(Object));
  });

  it('clears records and create access when native configure permission is removed', async () => {
    const wrapper = render();
    await flushPromises();
    await wrapper.setProps({ context: { capabilities: { configure: false } } });
    await flushPromises();
    expect(wrapper.find('[data-routing-row]').exists()).toBe(false);
    expect(wrapper.find('[data-routing-create]').exists()).toBe(false);
    expect(closeDialog).toHaveBeenCalled();
    expect(API.routingRules).toHaveBeenCalledTimes(1);
    expect(wrapper.get('[role=alert]').text()).toContain('COMMON.ERROR');
  });

  it('does not show a failed authorized query as a successful empty list', async () => {
    API.routingRules.mockRejectedValue({ response: { status: 404 } });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[role=alert]').text()).toContain('COMMON.ERROR');
    expect(wrapper.text()).not.toContain('COMMON.EMPTY');
    expect(wrapper.find('[data-routing-total]').exists()).toBe(false);
  });
});
