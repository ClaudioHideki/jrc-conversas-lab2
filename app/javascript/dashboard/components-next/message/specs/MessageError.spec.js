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
    additionalAttributes: ref({}),
  });
});

describe('WhatsApp failure explanation', () => {
  it.each([
    ['queued', 'queued'],
    ['submitting', 'Submitting'],
    ['unknown', 'unconfirmed'],
    ['failed', 'rejected'],
  ])(
    'shows persisted retry %s after reload without presenting it as sent or permitting another retry',
    (state, label) => {
      useMessageContext().additionalAttributes.value = {
        whatsappRetry: { attemptId: 55, originalMessageId: 101, state },
      };
      const wrapper = mount(MessageError, { props: { error: '' } });
      expect(wrapper.text()).toContain(label);
      expect(wrapper.text()).toContain('101');
      expect(wrapper.text()).not.toContain('Failed to send');
      expect(wrapper.find('button').exists()).toBe(false);
    }
  );

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

  it('explains a Meta experiment restriction while keeping manual retry available', () => {
    const wrapper = mount(MessageError, {
      props: { error: '130472: Synthetic experiment' },
    });
    expect(wrapper.text()).toContain('130472');
    expect(wrapper.text().toLowerCase()).toContain('experiment');
    expect(wrapper.text()).toContain('Meta');
    expect(wrapper.find('button').exists()).toBe(true);
  });

  it('permits a manual Cloud template retry outside the 24-hour service window', () => {
    const context = useMessageContext();
    context.createdAt.value = Math.floor(Date.now() / 1000) - 2 * 86400;
    context.additionalAttributes.value = {
      templateParams: { name: 'synthetic_retry' },
    };
    const wrapper = mount(MessageError, {
      props: { error: '130472: Synthetic experiment' },
    });
    expect(wrapper.find('button').exists()).toBe(true);
  });

  it('preserves the age limit for an ordinary message without template metadata', () => {
    useMessageContext().createdAt.value =
      Math.floor(Date.now() / 1000) - 2 * 86400;
    const wrapper = mount(MessageError, {
      props: { error: 'Synthetic ordinary error' },
    });
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('preserves the age limit for template metadata on a non-Cloud provider', () => {
    const context = useMessageContext();
    context.isWhatsappCloud.value = false;
    context.createdAt.value = Math.floor(Date.now() / 1000) - 2 * 86400;
    context.additionalAttributes.value = {
      templateParams: { name: 'synthetic_retry' },
    };
    const wrapper = mount(MessageError, {
      props: { error: 'Synthetic provider error' },
    });
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('preserves the existing retry control for the same error on a non-Cloud provider', () => {
    useMessageContext().isWhatsappCloud.value = false;
    const wrapper = mount(MessageError, {
      props: { error: '131026: Synthetic undeliverable' },
    });
    expect(wrapper.find('button').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('Verify the destination');
  });

  it('preserves a legacy failure when optional metadata is null', () => {
    useMessageContext().additionalAttributes.value = null;
    const wrapper = mount(MessageError, {
      props: { error: '131026: Synthetic destination' },
    });
    expect(wrapper.text()).toContain('131026');
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('retains the retry control for an unrelated existing error', () => {
    const wrapper = mount(MessageError, {
      props: { error: 'Synthetic email error' },
    });
    expect(wrapper.find('button').exists()).toBe(true);
  });
});
