import { afterEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { createMemoryHistory, createRouter } from 'vue-router';
import API from 'dashboard/api/jrcContactCenter';
import IvrDraftWorkspace from './IvrDraftWorkspace.vue';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { ivrDrafts: vi.fn() },
}));
enableAutoUnmount(afterEach);

describe('native IVR list URL history', () => {
  it('returns to the filtered first page through real router history after opening page two', async () => {
    const rows = Array.from({ length: 23 }, (_, index) => ({
      id: String(index + 1),
      unit_id: '1',
      name: `SYNTHETIC ${index}`,
      status: 'draft',
      revision: 1,
    }));
    API.ivrDrafts.mockImplementation((account, params) =>
      Promise.resolve({
        data: {
          items: Number(params.page) === 2 ? rows.slice(20) : rows.slice(0, 20),
          meta: {
            total: 23,
            page: Number(params.page),
            pages: 2,
            per_page: 20,
          },
        },
      })
    );
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        {
          path: '/app/accounts/:accountId/contact-center/ura',
          component: IvrDraftWorkspace,
        },
      ],
    });
    await router.push('/app/accounts/1/contact-center/ura');
    await router.isReady();
    const wrapper = mount(IvrDraftWorkspace, {
      props: { accountId: '1' },
      global: {
        plugins: [router],
        stubs: { IvrReferencePicker: true, IvrDraftEditor: true },
      },
    });
    await flushPromises();
    await wrapper.get('#ivr-search').setValue('SYNTHETIC');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(router.currentRoute.value.query.ivr_q).toBe('SYNTHETIC');
    await wrapper
      .get('[data-ivr-pagination]')
      .findAll('button')[1]
      .trigger('click');
    await flushPromises();
    expect(wrapper.findAll('[data-ivr-draft]')).toHaveLength(3);
    expect(router.currentRoute.value.query.ivr_page).toBe('2');
    router.back();
    await flushPromises();
    expect(wrapper.findAll('[data-ivr-draft]')).toHaveLength(20);
    expect(wrapper.get('#ivr-search').element.value).toBe('SYNTHETIC');
    expect(router.currentRoute.value.query.ivr_page).toBeUndefined();
    expect(API.ivrDrafts.mock.lastCall[1]).toMatchObject({
      q: 'SYNTHETIC',
      page: 1,
    });
  });
});
