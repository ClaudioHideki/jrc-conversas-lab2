import { beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AcwRuleTarget from './AcwRuleTarget.vue';
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { queues: vi.fn(), administrativeList: vi.fn() },
}));
const response = (items = []) => ({ data: { items, meta: { pages: 2 } } });
beforeEach(() => {
  vi.clearAllMocks();
  API.queues.mockResolvedValue(response([{ id: 2, name: 'SYNTHETIC Queue' }]));
  API.administrativeList.mockResolvedValue(response());
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
});
