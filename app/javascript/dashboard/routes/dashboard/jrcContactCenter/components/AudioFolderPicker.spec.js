import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AudioFolderPicker from './AudioFolderPicker.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { audioFolders: vi.fn() },
}));
const fixture = () =>
  mount(AudioFolderPicker, {
    props: {
      accountId: '1',
      unitId: '10',
      modelValue: '44',
      currentName: 'SYNTHETIC current folder',
    },
  });
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  API.audioFolders.mockResolvedValue({
    data: {
      items: [{ id: '90', name: 'SYNTHETIC destination' }],
      meta: { pages: 2 },
    },
  });
});

describe('audio destination picker only reads the currently authorized native unit', () => {
  it('retains an authorized current folder outside the first result page and emits exact string IDs', async () => {
    const wrapper = fixture();
    await flushPromises();
    expect(wrapper.get('option[value="44"]').text()).toBe(
      'SYNTHETIC current folder'
    );
    await wrapper.get('select').setValue('90');
    expect(wrapper.emitted('update:modelValue')).toEqual([['90']]);
    expect(API.audioFolders).toHaveBeenCalledWith('1', {
      unit_id: '10',
      q: '',
      page: 1,
      per_page: 20,
    });
  });

  it('paginates and resets the page when the destination search changes', async () => {
    const wrapper = fixture();
    await flushPromises();
    await wrapper.get('nav').findAll('button')[1].trigger('click');
    await flushPromises();
    expect(API.audioFolders).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ page: 2 })
    );
    await wrapper.get('input').setValue('SYNTHETIC searched');
    await flushPromises();
    expect(API.audioFolders).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ page: 1, q: 'SYNTHETIC searched' })
    );
  });

  it('discards a late response from a previous unit rather than displaying its private folder names', async () => {
    let resolve;
    API.audioFolders.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = fixture();
    await wrapper.setProps({ unitId: '11', modelValue: '', currentName: '' });
    await flushPromises();
    resolve({
      data: {
        items: [{ id: '99', name: 'SYNTHETIC old private folder' }],
        meta: { pages: 1 },
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC old private folder');
    expect(API.audioFolders).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ unit_id: '11' })
    );
  });

  it.each([401, 403, 404])(
    'requests complete private-context cleanup on a native %i denial',
    async status => {
      API.audioFolders.mockRejectedValueOnce({ response: { status } });
      const wrapper = fixture();
      await flushPromises();
      expect(wrapper.emitted('denied')).toHaveLength(1);
      expect(wrapper.get('select').element.disabled).toBe(true);
      expect(wrapper.find('option[value="90"]').exists()).toBe(false);
    }
  );
});
