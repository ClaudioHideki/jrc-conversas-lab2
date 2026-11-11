import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import MessageError from '../MessageError.vue';
import { useMessageContext } from '../provider';

vi.mock('../provider', () => ({ useMessageContext: vi.fn() }));

beforeEach(() => {
  useMessageContext.mockReturnValue({
    isWhatsappCloud: ref(true),
    orientation: ref('right'),
    status: ref('failed'),
    createdAt: ref(Math.floor(Date.now() / 1000)),
    content: ref('Synthetic'),
    attachments: ref([]),
    meta: ref({}),
  });
});

describe('WhatsApp failure explanation', () => {
  it.each([
    ['131049: Synthetic restriction', 'marketing'],
    ['131026: Synthetic undeliverable', 'destination'],
  ])(
    'keeps the technical error %s and explains the required review after reload',
    (error, explanation) => {
      const wrapper = mount(MessageError, { props: { error } });
      expect(wrapper.text()).toContain(error);
      expect(wrapper.text().toLowerCase()).toContain(explanation);
      expect(wrapper.find('button').exists()).toBe(false);
    }
  );

  it('shows a denied retry explanation while retaining the provider error', () => {
    const context = useMessageContext();
    context.meta.value = { error: 'Retry blocked for review' };
    const wrapper = mount(MessageError, {
      props: { error: 'Synthetic timeout' },
    });
    expect(wrapper.text()).toContain('Synthetic timeout');
    expect(wrapper.text()).toContain('Retry blocked for review');
  });

  it('preserves the existing retry control for the same error on a non-Cloud provider', () => {
    useMessageContext().isWhatsappCloud.value = false;
    const wrapper = mount(MessageError, { props: { error: '131026: Synthetic undeliverable' } });
    expect(wrapper.find('button').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('Verify the destination');
  });

  it('retains the retry control for an unrelated existing error', () => {
    const wrapper = mount(MessageError, {
      props: { error: 'Synthetic email error' },
    });
    expect(wrapper.find('button').exists()).toBe(true);
  });
});
