import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import Configuration from './EndingServiceDeskConfiguration.vue';
import Lookup from './__fixtures__/EndingLookupBoundary.vue';
import Catalogue from './__fixtures__/EndingCatalogueBoundary.vue';

// Unit boundaries only. Real policy, catalogue/API and Chrome proof are separate.
const holder = vi.hoisted(() => ({ current: null }));
vi.mock('../../serviceDesk/composables/useServiceDesk', () => ({
  provideServiceDesk: () => holder.current,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const props = () => ({
  accountId: '1',
  options: {
    configuration_available: true,
    unit: { id: '11', name: 'SYNTHETIC mapped unit' },
  },
});
const open = (extra = {}) =>
  mount(Configuration, {
    props: { ...props(), ...extra },
    global: {
      stubs: {
        LookupSelect: Lookup,
        CatalogueAnswers: Catalogue,
        ServiceDefinitionSelect: true,
        ServiceDeskState: true,
      },
    },
  });
const lookup = (wrapper, resource) =>
  wrapper
    .findAllComponents(Lookup)
    .find(item => item.props('resource') === resource);
const ready = async wrapper => {
  await flushPromises();
  await wrapper
    .get('[data-ending-service-desk-title]')
    .setValue('SYNTHETIC reviewed title');
  await wrapper
    .get('[data-ending-service-desk-description]')
    .setValue('SYNTHETIC reviewed description');
  lookup(wrapper, 'priorities').vm.$emit('update:modelValue', '12');
  await flushPromises();
};
const confirm = wrapper =>
  wrapper.get('[data-ending-service-desk-reviewed]').setValue(true);
const apply = wrapper => wrapper.get('[data-ending-service-desk-apply]');

beforeEach(() => {
  holder.current = {
    state: reactive({
      status: 'ready',
      context: {
        account_id: '1',
        user_id: '4',
        effective_permissions: ['jrc_service_desk_customers_view'],
        units: [
          {
            id: '11',
            name: 'SYNTHETIC mapped unit',
            initial_status: { id: '10', name: 'SYNTHETIC open' },
            permissions: { create_ticket: true, assign_ticket: true },
          },
        ],
      },
    }),
  };
});

describe('Existing native Service Desk controls in an ending rule template', () => {
  it('requires native context, catalogue validity and explicit review before applying parameters to the outer rule', async () => {
    const wrapper = open();
    expect(apply(wrapper).element.disabled).toBe(true);
    await ready(wrapper);
    expect(apply(wrapper).element.disabled).toBe(true);
    await confirm(wrapper);
    expect(apply(wrapper).element.disabled).toBe(false);
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('save')).toEqual([
      [
        {
          unit_id: '11',
          service_id: null,
          attributes: {
            title: 'SYNTHETIC reviewed title',
            description: 'SYNTHETIC reviewed description',
            service_fields: {},
            status_id: '10',
            priority_id: '12',
          },
        },
      ],
    ]);
    expect(wrapper.emitted('cancel')).toBeUndefined();
  });

  it('does not render private template fields for a different mapped unit', async () => {
    const wrapper = open({
      value: {
        unit_id: '22',
        service_id: null,
        attributes: { title: 'SYNTHETIC hidden other unit' },
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-ending-service-desk-title]').exists()).toBe(
      false
    );
    expect(wrapper.text()).not.toContain('SYNTHETIC hidden other unit');
    expect(apply(wrapper).element.disabled).toBe(true);
    expect(wrapper.emitted('save')).toBeUndefined();
  });

  it('withdraws controls after current native permissions are removed and does not retain a usable review', async () => {
    const wrapper = open();
    await ready(wrapper);
    await confirm(wrapper);
    holder.current.state.context.effective_permissions = [];
    await flushPromises();
    expect(wrapper.find('[data-ending-service-desk-title]').exists()).toBe(
      false
    );
    expect(apply(wrapper).element.disabled).toBe(true);
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('save')).toBeUndefined();
    holder.current.state.context.effective_permissions = [
      'jrc_service_desk_customers_view',
    ];
    await flushPromises();
    expect(
      wrapper.get('[data-ending-service-desk-reviewed]').element.checked
    ).toBe(false);
    expect(apply(wrapper).element.disabled).toBe(true);
  });

  it('does not treat native context from another account as an authorization', async () => {
    const wrapper = open({ accountId: '2' });
    await flushPromises();
    expect(wrapper.find('[data-ending-service-desk-title]').exists()).toBe(
      false
    );
    expect(apply(wrapper).element.disabled).toBe(true);
    expect(wrapper.emitted('save')).toBeUndefined();
  });

  it('requires a server-authorized source mapping even when the native destination module is available', async () => {
    const wrapper = open({ options: { configuration_available: false } });
    await flushPromises();
    expect(wrapper.find('[data-ending-service-desk-title]').exists()).toBe(
      false
    );
    expect(apply(wrapper).element.disabled).toBe(true);
    expect(wrapper.emitted('save')).toBeUndefined();
  });

  it('invalidates explicit review when any parameter changes', async () => {
    const wrapper = open();
    await ready(wrapper);
    await confirm(wrapper);
    expect(apply(wrapper).element.disabled).toBe(false);
    await wrapper
      .get('[data-ending-service-desk-title]')
      .setValue('SYNTHETIC changed after review');
    expect(
      wrapper.get('[data-ending-service-desk-reviewed]').element.checked
    ).toBe(false);
    expect(apply(wrapper).element.disabled).toBe(true);
  });

  it('keeps entered values and the form available when the native catalogue becomes invalid', async () => {
    const wrapper = open();
    await ready(wrapper);
    await confirm(wrapper);
    wrapper.findComponent(Catalogue).vm.$emit('ready', false);
    await flushPromises();
    expect(apply(wrapper).element.disabled).toBe(true);
    expect(wrapper.get('[data-ending-service-desk-title]').element.value).toBe(
      'SYNTHETIC reviewed title'
    );
    expect(wrapper.emitted('save')).toBeUndefined();
    expect(wrapper.emitted('cancel')).toBeUndefined();
  });

  it('does not invent assignment rights or silently remove a previously reviewed assignment', async () => {
    holder.current.state.context.units[0].permissions.assign_ticket = false;
    const value = {
      unit_id: '11',
      service_id: null,
      attributes: {
        title: 'SYNTHETIC existing',
        description: 'SYNTHETIC existing',
        status_id: '10',
        priority_id: '12',
        queue_id: '21',
        service_fields: {},
      },
    };
    const wrapper = open({ value });
    await flushPromises();
    await confirm(wrapper);
    expect(lookup(wrapper, 'assignees')).toBeUndefined();
    expect(apply(wrapper).element.disabled).toBe(true);
    expect(value.attributes.queue_id).toBe('21');
    expect(wrapper.emitted('save')).toBeUndefined();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'ASSIGNMENT_REQUIRED'
    );
    holder.current.state.context.units[0].permissions.assign_ticket = true;
    await flushPromises();
    expect(
      wrapper.get('[data-ending-service-desk-reviewed]').element.checked
    ).toBe(false);
    expect(apply(wrapper).element.disabled).toBe(true);
    expect(value.attributes.queue_id).toBe('21');
  });

  it('reuses native paginated lookups with authorized persisted labels and current assignment filters', async () => {
    const value = {
      unit_id: '11',
      service_id: null,
      attributes: {
        title: 'SYNTHETIC existing',
        description: 'SYNTHETIC existing',
        status_id: '10',
        priority_id: '12',
        queue_id: '21',
        team_id: '31',
        assignee_account_user_id: '41',
        service_fields: {},
      },
    };
    const wrapper = open({
      value,
      labels: {
        priority: { id: '12', name: 'SYNTHETIC selected outside page' },
      },
    });
    await flushPromises();
    expect(lookup(wrapper, 'priorities').props('currentName')).toBe(
      'SYNTHETIC selected outside page'
    );
    expect(lookup(wrapper, 'assignees').props()).toMatchObject({
      unitId: '11',
      teamId: '31',
      queueId: '21',
    });
    expect(wrapper.emitted('save')).toBeUndefined();
  });
  it('updates only the editable draft to the current native initial status and requires a new review', async () => {
    const value = {
      unit_id: '11',
      service_id: null,
      attributes: {
        title: 'SYNTHETIC historical rule',
        description: 'SYNTHETIC historical description',
        status_id: '9',
        priority_id: '12',
        service_fields: {},
      },
    };
    const wrapper = open({ value });
    await ready(wrapper);
    await confirm(wrapper);
    expect(apply(wrapper).element.disabled).toBe(false);
    holder.current.state.context.units[0].initial_status = {
      id: '14',
      name: 'SYNTHETIC current initial status',
    };
    await flushPromises();
    expect(value.attributes.status_id).toBe('9');
    expect(apply(wrapper).element.disabled).toBe(true);
    expect(wrapper.emitted('save')).toBeUndefined();
    await confirm(wrapper);
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('save')[0][0].attributes.status_id).toBe('14');
    expect(value.attributes.status_id).toBe('9');
  });

  it('requires an existing initial status and a fresh review after that native status is restored', async () => {
    holder.current.state.context.units[0].initial_status = null;
    const wrapper = open();
    await ready(wrapper);
    await confirm(wrapper);
    expect(apply(wrapper).element.disabled).toBe(true);
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'INITIAL_STATUS_REQUIRED'
    );
    expect(wrapper.emitted('save')).toBeUndefined();
    const initial = { id: '10', name: 'SYNTHETIC restored initial' };
    holder.current.state.context.units[0].initial_status = initial;
    await flushPromises();
    expect(apply(wrapper).element.disabled).toBe(true);
    await confirm(wrapper);
    expect(apply(wrapper).element.disabled).toBe(false);
    holder.current.state.context.units[0].initial_status = null;
    await flushPromises();
    expect(apply(wrapper).element.disabled).toBe(true);
    holder.current.state.context.units[0].initial_status = initial;
    await flushPromises();
    expect(
      wrapper.get('[data-ending-service-desk-reviewed]').element.checked
    ).toBe(false);
    expect(apply(wrapper).element.disabled).toBe(true);
    expect(wrapper.get('[data-ending-service-desk-title]').element.value).toBe(
      'SYNTHETIC reviewed title'
    );
    expect(wrapper.emitted('save')).toBeUndefined();
  });

  it('clears stale subcategory and assignee after native parent selections change and requires a new review', async () => {
    const value = {
      unit_id: '11',
      service_id: null,
      attributes: {
        title: 'SYNTHETIC existing',
        description: 'SYNTHETIC existing',
        status_id: '10',
        priority_id: '12',
        category_id: '21',
        subcategory_id: '22',
        team_id: '31',
        assignee_account_user_id: '41',
        service_fields: {},
      },
    };
    const wrapper = open({ value });
    await flushPromises();
    await confirm(wrapper);
    lookup(wrapper, 'categories').vm.$emit('update:modelValue', '23');
    lookup(wrapper, 'teams').vm.$emit('update:modelValue', '32');
    await flushPromises();
    const subcategory = wrapper
      .findAllComponents(Lookup)
      .filter(item => item.props('resource') === 'categories')[1];
    expect(subcategory.props('modelValue')).toBe('');
    expect(lookup(wrapper, 'assignees').props('modelValue')).toBe('');
    expect(apply(wrapper).element.disabled).toBe(true);
    expect(wrapper.emitted('save')).toBeUndefined();
    expect(value.attributes.subcategory_id).toBe('22');
    expect(value.attributes.assignee_account_user_id).toBe('41');
    await confirm(wrapper);
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('save')[0][0].attributes).toMatchObject({
      category_id: '23',
      team_id: '32',
    });
    expect(wrapper.emitted('save')[0][0].attributes).not.toHaveProperty(
      'subcategory_id'
    );
    expect(wrapper.emitted('save')[0][0].attributes).not.toHaveProperty(
      'assignee_account_user_id'
    );
  });
});
