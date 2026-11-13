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
    ['131049: Synthetic restriction', 0],
    ['131026: Synthetic undeliverable', 0],
    ['131049: Synthetic restriction', 2 * 86400],
    ['131026: Synthetic undeliverable', 2 * 86400],
  ])(
    'allows a manual template retry for %s at age %s without an inline explanation',
    (error, age) => {
      const context = useMessageContext();
      context.createdAt.value = Math.floor(Date.now() / 1000) - age;
      context.additionalAttributes.value = {
        templateParams: { name: 'synthetic_retry' },
      };
      const wrapper = mount(MessageError, { props: { error } });
      expect(wrapper.text()).toContain(error);
      expect(wrapper.text()).toContain('Failed to send');
      expect(wrapper.find('[role="status"]').exists()).toBe(false);
      expect(wrapper.find('button').exists()).toBe(true);
      wrapper.find('button').trigger('click');
      expect(wrapper.emitted('retry')).toHaveLength(1);
    }
  );

  it('keeps failure details in the tooltip without adding a paragraph to the conversation', () => {
    const context = useMessageContext();
    context.meta.value = { error: 'Retry blocked for review' };
    const wrapper = mount(MessageError, {
      props: { error: 'Synthetic timeout' },
    });
    const tooltip = wrapper.find('.group > .absolute');
    expect(tooltip.text()).toContain('Synthetic timeout');
    expect(tooltip.text()).toContain('Retry blocked for review');
    expect(wrapper.text()).toContain('Failed to send');
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
  });

  it('shows a backend denial in the tooltip when no provider error is present', () => {
    useMessageContext().meta.value = {
      error: 'Retry unavailable during cooldown',
    };
    const wrapper = mount(MessageError, { props: { error: '' } });
    const tooltip = wrapper.find('.group > .absolute');
    expect(tooltip.exists()).toBe(true);
    expect(tooltip.text()).toContain('Retry unavailable during cooldown');
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
  });

  it('preserves the provider error when legacy metadata is null', () => {
    useMessageContext().meta.value = null;
    const wrapper = mount(MessageError, {
      props: { error: 'Synthetic provider failure' },
    });
    expect(wrapper.find('.group > .absolute').text()).toContain(
      'Synthetic provider failure'
    );
  });

  it('keeps manual experiment retry available without adding a policy explanation', () => {
    const wrapper = mount(MessageError, {
      props: { error: '130472: Synthetic experiment' },
    });
    expect(wrapper.text()).toContain('130472');
    expect(wrapper.text().toLowerCase()).toContain('experiment');
    expect(wrapper.text()).not.toContain('Meta');
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
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
