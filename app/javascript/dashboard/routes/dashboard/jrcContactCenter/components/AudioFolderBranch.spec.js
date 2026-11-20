import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AudioFolderBranch from './AudioFolderBranch.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { audioFolders: vi.fn() },
}));
const folder = {
  id: '9',
  unit_id: '10',
  parent_id: null,
  name: 'SYNTHETIC root',
};
const child = {
  id: '11',
  unit_id: '10',
  parent_id: '9',
  name: 'SYNTHETIC child',
};
const payload = (items = [child], values = {}) => ({
  data: {
    account_id: '1',
    items,
    meta: {
      page: 1,
      pages: items.length ? 1 : 0,
      total: items.length,
      ...values,
    },
  },
});
const setup = () =>
  mount(AudioFolderBranch, {
    props: { accountId: '1', unitId: '10', folder, canManage: true },
  });
const expand = wrapper =>
  wrapper.get('[data-expand-audio-folder="9"]').trigger('click');
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.resetAllMocks();
  API.audioFolders.mockResolvedValue(payload());
});

describe('scoped folder disclosure (transport fixtures, not native persistence proof)', () => {
  it('loads children only on explicit expansion and preserves native navigation and editing', async () => {
    const wrapper = setup();
    expect(API.audioFolders).not.toHaveBeenCalled();
    expect(
      wrapper.get('[data-expand-audio-folder="9"]').attributes('aria-expanded')
    ).toBe('false');
    await expand(wrapper);
    await flushPromises();
    expect(API.audioFolders).toHaveBeenCalledTimes(1);
    expect(API.audioFolders).toHaveBeenCalledWith('1', {
      unit_id: '10',
      parent_id: '9',
      page: 1,
      per_page: 20,
    });
    expect(
      wrapper.get('[data-audio-folder-children="9"]').attributes('id')
    ).toBe(
      wrapper.get('[data-expand-audio-folder="9"]').attributes('aria-controls')
    );
    await wrapper.get('[data-open-audio-folder="11"]').trigger('click');
    await wrapper.get('[data-edit-audio-folder="11"]').trigger('click');
    expect(wrapper.emitted('navigate')).toEqual([['11']]);
    expect(wrapper.emitted('edit')).toEqual([[child]]);
  });

  it('discards a collapsed response and performs a fresh authorized read after re-expansion', async () => {
    let finish;
    API.audioFolders.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = setup();
    await expand(wrapper);
    await expand(wrapper);
    finish(payload());
    await flushPromises();
    expect(wrapper.find('[data-audio-folder="11"]').exists()).toBe(false);
    expect(wrapper.find('[data-audio-folder-children="9"]').exists()).toBe(
      false
    );
    await expand(wrapper);
    await flushPromises();
    expect(API.audioFolders).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-audio-folder="11"]').exists()).toBe(true);
  });

  it.each([{ accountId: '2' }, { unitId: '20' }, { canManage: false }])(
    'discards previous-scope responses after context change %j',
    async change => {
      let finish;
      API.audioFolders.mockImplementationOnce(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      );
      const wrapper = setup();
      await expand(wrapper);
      await wrapper.setProps(change);
      finish(payload());
      await flushPromises();
      expect(wrapper.find('[data-audio-folder="11"]').exists()).toBe(false);
      expect(
        wrapper
          .get('[data-expand-audio-folder="9"]')
          .attributes('aria-expanded')
      ).toBe('false');
    }
  );

  it.each([401, 403, 404])(
    'clears the branch and propagates native access denial %i',
    async status => {
      API.audioFolders.mockRejectedValueOnce({ response: { status } });
      const wrapper = setup();
      await expand(wrapper);
      await flushPromises();
      expect(wrapper.emitted('denied')).toEqual([[]]);
      expect(wrapper.find('[data-audio-folder-children="9"]').exists()).toBe(
        false
      );
    }
  );

  it.each([
    { ...payload().data, account_id: '2' },
    { ...payload().data, items: [{ ...child, unit_id: '20' }] },
    { ...payload().data, items: [{ ...child, parent_id: '12' }] },
  ])(
    'never renders a mismatched account, unit or parent response',
    async data => {
      API.audioFolders.mockResolvedValueOnce({ data });
      const wrapper = setup();
      await expand(wrapper);
      await flushPromises();
      expect(wrapper.find('[data-audio-folder="11"]').exists()).toBe(false);
      expect(wrapper.get('[role="alert"]').text()).toBe(
        'JRC_CONTACT_CENTER.AUDIO_FOLDERS.ERROR'
      );
    }
  );

  it('keeps native bounded pagination and corrects a shrinking page only once', async () => {
    API.audioFolders.mockResolvedValueOnce(
      payload([child], { pages: 2, total: 21 })
    );
    const wrapper = setup();
    await expand(wrapper);
    await flushPromises();
    API.audioFolders.mockResolvedValueOnce(
      payload([], { page: 2, pages: 1, total: 1 })
    );
    API.audioFolders.mockResolvedValueOnce(payload());
    await wrapper.get('nav').findAll('button').at(-1).trigger('click');
    await flushPromises();
    expect(
      API.audioFolders.mock.calls.map(([, values]) => values.page)
    ).toEqual([1, 2, 1]);
    expect(wrapper.find('[data-audio-folder="11"]').exists()).toBe(true);
    expect(wrapper.find('nav').exists()).toBe(false);
  });

  it('collapses after native denial in a nested branch without reading another parent', async () => {
    const wrapper = setup();
    await expand(wrapper);
    await flushPromises();
    API.audioFolders.mockRejectedValueOnce({ response: { status: 403 } });
    await wrapper.get('[data-expand-audio-folder="11"]').trigger('click');
    await flushPromises();
    expect(API.audioFolders).toHaveBeenLastCalledWith('1', {
      unit_id: '10',
      parent_id: '11',
      page: 1,
      per_page: 20,
    });
    expect(wrapper.emitted('denied')).toEqual([[]]);
    expect(wrapper.find('[data-audio-folder="11"]').exists()).toBe(false);
  });
});
