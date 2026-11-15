import { shallowMount } from '@vue/test-utils';
import CannedResponse from '../CannedResponse.vue';
describe('existing slash quick-reply compatibility', () => {
  const records = [
    {
      id: 1,
      account_id: 10,
      short_code: 'image',
      content: 'Hello',
      file: { filename: 'safe.png' },
    },
    {
      id: 2,
      account_id: 99,
      short_code: 'foreign',
      content: 'Private old account',
    },
  ];
  it('routes the model ID to review without silently inserting only the text', () => {
    const wrapper = shallowMount(CannedResponse, {
      props: { reviewBeforeInsert: true },
      global: {
        mocks: {
          $store: {
            getters: { getCannedResponses: records, getCurrentAccountId: 10 },
            dispatch: vi.fn(),
          },
        },
      },
    });
    expect(wrapper.vm.items).toHaveLength(1);
    wrapper.vm.handleMentionClick(wrapper.vm.items[0]);
    expect(wrapper.emitted('review')).toEqual([[1]]);
    expect(wrapper.emitted('replace')).toBeUndefined();
  });
  it('preserves the old text replacement contract in other editor contexts', () => {
    const wrapper = shallowMount(CannedResponse, {
      global: {
        mocks: {
          $store: {
            getters: { getCannedResponses: records, getCurrentAccountId: 10 },
            dispatch: vi.fn(),
          },
        },
      },
    });
    wrapper.vm.handleMentionClick({ description: 'Legacy {{ contact.name }}' });
    expect(wrapper.emitted('replace')).toEqual([['Legacy {{ contact.name }}']]);
    expect(wrapper.emitted('review')).toBeUndefined();
  });
});
