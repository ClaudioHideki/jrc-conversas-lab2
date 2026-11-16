import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, reactive, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AdministrationSection from './AdministrationSection.vue';
import ControlDeskPage from '../views/ControlDeskPage.vue';

const mocks = vi.hoisted(() => ({ route: null, replace: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    administration: vi.fn(),
    units: vi.fn(),
    queues: vi.fn(),
    queueMemberships: vi.fn(),
    administrativeList: vi.fn(),
    saveUnit: vi.fn(),
    saveQueue: vi.fn(),
    saveQueueMembership: vi.fn(),
    acwPolicy: vi.fn(),
    updateAcwPolicy: vi.fn(),
  },
}));
const Dialog = defineComponent({
  emits: ['confirm'],
  setup(_props, { expose, emit }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
      close: () => {
        visible.value = false;
      },
    });
    return { visible, confirm: () => emit('confirm'), label: 'SAVE' };
  },
  template:
    '<form v-if="visible" data-dialog @submit.prevent="confirm"><slot /><button data-submit type="submit">{{ label }}</button></form>',
});
enableAutoUnmount(afterEach);
const context = {
  capabilities: { configure: true },
  units: [{ id: 1, name: 'Authorized' }],
  queues: [],
  corporate: { companies: [], units: [] },
};
const mountSection = (key = 'general', state = 'available') =>
  mount(AdministrationSection, {
    props: { accountId: '1', card: { key, state }, context },
    global: { stubs: { Dialog, RouterLink: true } },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1' }, query: {} });
  API.units.mockResolvedValue({
    data: { items: [], meta: { page: 1, pages: 0, total: 0 } },
  });
  API.queues.mockResolvedValue({ data: { items: [] } });
  API.saveUnit.mockResolvedValue({ data: {} });
});

describe('administrative workflow', () => {
  it('preserves a failed creation draft and persists the reviewed values on retry', async () => {
    const wrapper = mountSection();
    await flushPromises();
    await wrapper.get('[data-create]').trigger('click');
    await flushPromises();
    const inputs = wrapper.findAll('[data-dialog] input');
    await inputs[0].setValue('Synthetic unit');
    await inputs[1].setValue('SYNTHETIC');
    API.saveUnit.mockRejectedValueOnce({
      response: { data: { message: 'Conflict' } },
    });
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe('Conflict');
    expect(inputs[0].element.value).toBe('Synthetic unit');
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(API.saveUnit).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ name: 'Synthetic unit', code: 'SYNTHETIC' }),
      undefined
    );
    expect(wrapper.find('[data-dialog]').exists()).toBe(false);
  });

  it('edits loaded values without changing the list object before persistence', async () => {
    const unit = {
      id: 10,
      name: 'Original',
      code: 'ORIGINAL',
      kind: 'sac',
      timezone: 'UTC',
      status: 'active',
      settings: {},
    };
    API.units.mockResolvedValue({ data: { items: [unit] } });
    const wrapper = mountSection();
    await flushPromises();
    await wrapper.get('[data-edit]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-dialog] input').setValue('Revised');
    expect(unit.name).toBe('Original');
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(API.saveUnit).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({ name: 'Revised', timezone: 'UTC' }),
      10
    );
  });

  it('restores pagination and filters from the URL and clears them explicitly', async () => {
    mocks.route.query = {
      units_page: '2',
      units_q: 'finance',
      units_status: 'inactive',
    };
    const wrapper = mountSection();
    await flushPromises();
    expect(API.units).toHaveBeenCalledWith('1', {
      page: 2,
      per_page: 20,
      q: 'finance',
      status: 'inactive',
    });
    await wrapper.findAll('form button')[1].trigger('click');
    expect(mocks.replace).toHaveBeenCalledWith({
      query: { units_page: 1, units_q: undefined, units_status: undefined },
    });
  });

  it('does not present fake controls or counters for a pending provider capability', async () => {
    const wrapper = mountSection('ivr', 'pending_contract');
    await flushPromises();
    expect(wrapper.find('[data-create]').exists()).toBe(false);
    expect(wrapper.find('form').exists()).toBe(false);
    expect(API.administrativeList).not.toHaveBeenCalled();
    expect(wrapper.get('[role="status"]').text()).toBe(
      'JRC_CONTACT_CENTER.ADMIN.PENDING'
    );
  });

  it('prevents a repeated submit while persistence is in flight', async () => {
    let finish;
    API.saveUnit.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mountSection();
    await flushPromises();
    await wrapper.get('[data-create]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-dialog]').trigger('submit');
    await wrapper.get('[data-dialog]').trigger('submit');
    expect(API.saveUnit).toHaveBeenCalledTimes(1);
    finish({ data: {} });
    await flushPromises();
  });

  it('discards late administrative data after switching account', async () => {
    let finish;
    API.administration
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      )
      .mockResolvedValueOnce({
        data: { cards: [], capabilities: {}, provider: {} },
      });
    const wrapper = mount(ControlDeskPage, {
      global: { stubs: { RouterLink: true } },
    });
    mocks.route.params.accountId = '2';
    await flushPromises();
    finish({
      data: {
        cards: [{ key: 'general', state: 'available', count: 999 }],
        capabilities: { configure: true },
        provider: {},
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-card="general"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('999');
  });
});
