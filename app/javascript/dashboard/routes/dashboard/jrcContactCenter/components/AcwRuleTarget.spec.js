import { beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AcwRuleTarget from './AcwRuleTarget.vue';
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { queues: vi.fn(), units: vi.fn(), administrativeList: vi.fn() },
}));
const response = (items = []) => ({ data: { items, meta: { pages: 2 } } });
beforeEach(() => {
  vi.clearAllMocks();
  API.queues.mockResolvedValue(response([{ id: 2, name: 'SYNTHETIC Queue' }]));
  API.administrativeList.mockResolvedValue(response());
  API.units.mockResolvedValue(response([{ id: 3, name: 'SYNTHETIC Unit' }]));
});
describe('native scoped ACW target lookup', () => {
  it('uses the existing queue scope with native bounded pagination and selection', async () => {
    const wrapper = mount(AcwRuleTarget, {
      props: { accountId: 1, scope: 'queue' },
    });
    await flushPromises();
    expect(API.queues).toHaveBeenCalledWith(1, {
      q: '',
      page: 1,
      per_page: 20,
    });
    await wrapper.get('select').setValue('2');
    expect(wrapper.emitted('update:modelValue')[0]).toEqual(['2']);
    await wrapper.findAll('button')[1].trigger('click');
    await flushPromises();
    expect(API.queues).toHaveBeenLastCalledWith(1, {
      q: '',
      page: 2,
      per_page: 20,
    });
    wrapper.unmount();
  });
  it('uses the native authorized team listing instead of inventing team grants', async () => {
    const wrapper = mount(AcwRuleTarget, {
      props: { accountId: 1, scope: 'team' },
    });
    await flushPromises();
    expect(API.administrativeList).toHaveBeenCalledWith(1, 'teams', {
      q: '',
      page: 1,
      per_page: 20,
    });
    expect(API.queues).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('does not restore a late result from the previous account', async () => {
    let finish;
    API.queues.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mount(AcwRuleTarget, {
      props: { accountId: 1, scope: 'queue' },
    });
    await wrapper.setProps({ accountId: 2 });
    await flushPromises();
    finish(response([{ id: 9, name: 'SYNTHETIC OLD PRIVATE' }]));
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC OLD PRIVATE');
    expect(API.queues).toHaveBeenLastCalledWith(2, {
      q: '',
      page: 1,
      per_page: 20,
    });
    wrapper.unmount();
  });
  it('preserves the selected reference and reports a denied or failed lookup', async () => {
    API.queues.mockRejectedValueOnce({ response: { status: 401 } });
    const wrapper = mount(AcwRuleTarget, {
      props: { accountId: 1, scope: 'queue', modelValue: '7' },
    });
    await flushPromises();
    expect(wrapper.get('[role="alert"]').exists()).toBe(true);
    expect(wrapper.get('select').element.value).toBe('7');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    wrapper.unmount();
  });
  it('uses real native unit options instead of looking up administrative teams', async () => {
    const wrapper = mount(AcwRuleTarget, {
      props: { accountId: 1, scope: 'unit', required: false },
    });
    await flushPromises();
    expect(API.units).toHaveBeenCalledWith(1, { q: '', page: 1, per_page: 20 });
    expect(API.administrativeList).not.toHaveBeenCalled();
    expect(API.queues).not.toHaveBeenCalled();
    await wrapper.get('select').setValue('3');
    expect(wrapper.emitted('update:modelValue')[0]).toEqual(['3']);
    wrapper.unmount();
  });
  it('preserves required targets for existing ACW editors while allowing optional recording filters', async () => {
    const wrapper = mount(AcwRuleTarget, {
      props: { accountId: 1, scope: 'queue' },
    });
    await flushPromises();
    expect(wrapper.get('select').element.required).toBe(true);
    await wrapper.setProps({ required: false });
    expect(wrapper.get('select').element.required).toBe(false);
    expect(wrapper.get('select').element.value).toBe('');
    wrapper.unmount();
  });
  it('withdraws previous unit labels while a changed account native lookup is pending', async () => {
    let finish;
    API.units.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mount(AcwRuleTarget, {
      props: { accountId: 1, scope: 'unit', required: false },
    });
    await wrapper.setProps({ accountId: 2 });
    await flushPromises();
    finish(response([{ id: 9, name: 'SYNTHETIC denied old unit' }]));
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC denied old unit');
    expect(API.units).toHaveBeenLastCalledWith(2, {
      q: '',
      page: 1,
      per_page: 20,
    });
    wrapper.unmount();
  });
  it.each([
    ['unit', 'UNIT'],
    ['queue', 'QUEUE'],
    ['team', 'TEAM'],
  ])(
    'uses the actual %s resource labels without presenting an unrelated queue/team prompt',
    async (scope, key) => {
      const wrapper = mount(AcwRuleTarget, { props: { accountId: 1, scope } });
      await flushPromises();
      const labels = wrapper.findAll('label');
      expect(labels[0].text()).toContain(
        `JRC_CONTACT_CENTER.ACW_RULES.${key}_SEARCH`
      );
      expect(labels[1].text()).toContain(
        `JRC_CONTACT_CENTER.ACW_RULES.${key}_TARGET`
      );
      expect(wrapper.text()).not.toContain(
        'JRC_CONTACT_CENTER.ACW_RULES.TARGET_SEARCH'
      );
      wrapper.unmount();
    }
  );
});
