import { ref } from 'vue';
import { config, shallowMount } from '@vue/test-utils';
import MessageMeta from '../MessageMeta.vue';
import MessageStatus from '../MessageStatus.vue';
import { useMessageContext } from '../provider';
import { useInbox } from 'dashboard/composables/useInbox';

vi.mock('../provider', () => ({ useMessageContext: vi.fn() }));
vi.mock('dashboard/composables/useInbox', () => ({ useInbox: vi.fn() }));

beforeEach(() => {
  useInbox.mockReturnValue(
    Object.fromEntries(
      [
        'isAPIInbox',
        'isAFacebookInbox',
        'isALineChannel',
        'isASmsInbox',
        'isATelegramChannel',
        'isATwilioChannel',
        'isAWebWidgetInbox',
        'isAWhatsAppChannel',
        'isAnEmailChannel',
        'isAnInstagramChannel',
        'isATiktokChannel',
      ].map(key => [key, ref(key === 'isAPIInbox')])
    )
  );
  useMessageContext.mockReturnValue({
    status: ref('sent'),
    isPrivate: ref(false),
    createdAt: ref(1),
    sourceId: ref(null),
    messageType: ref(1),
    contentAttributes: ref({}),
  });
});

describe('Broker outbound delivery evidence', () => {
  it.each(['DELIVERED', 'READ'])(
    'shows a committed direct provider %s without a Broker canonical ID',
    state => {
      useMessageContext().contentAttributes.value = {
        jrcBrokerLegacyUnconfirmed: true,
        jrcDeliveryProjection: { kind: 'DIRECT_EVOLUTION_RECEIPT_V1', state },
      };
      const indicator = shallowMount(MessageMeta).findComponent(MessageStatus);
      expect(indicator.props('status')).toBe(state.toLowerCase());
      expect(indicator.props('statusLabel')).toBe('');
    }
  );

  it('retains the clock for an unsupported direct provider state', () => {
    useMessageContext().contentAttributes.value = {
      jrcBrokerOutbound: { version: 1, state: 'PENDING' },
      jrcDeliveryProjection: {
        kind: 'DIRECT_EVOLUTION_RECEIPT_V1',
        state: 'SENT',
      },
    };
    expect(
      shallowMount(MessageMeta).findComponent(MessageStatus).props('status')
    ).toBe('progress');
  });
  it('keeps a pre-upgrade durable reply unconfirmed using read-only display evidence', () => {
    useMessageContext().contentAttributes.value = {
      jrcBrokerLegacyUnconfirmed: true,
    };
    const wrapper = shallowMount(MessageMeta);
    expect(wrapper.findComponent(MessageStatus).props('status')).toBe(
      'progress'
    );
    expect(wrapper.findComponent(MessageStatus).props('statusLabel')).toBe(
      'WhatsApp send not confirmed'
    );
  });

  it.each([
    ['pending', 'Na fila do WhatsApp'],
    ['accepted', 'Aguardando confirmação do WhatsApp'],
    ['unknown', 'Envio pelo WhatsApp não confirmado'],
  ])(
    'shows the %s state in Portuguese without English fallback',
    (outcome, label) => {
      const locale = config.global.plugins[0].global.locale;
      const previous = locale.value;
      locale.value = 'pt_BR';
      try {
        useMessageContext().contentAttributes.value = {
          jrcBrokerOutbound: { version: 1, state: 'PENDING' },
          jrcBrokerDelivery: { version: 1, outcome },
        };
        expect(
          shallowMount(MessageMeta)
            .findComponent(MessageStatus)
            .props('statusLabel')
        ).toBe(label);
      } finally {
        locale.value = previous;
      }
    }
  );

  it.each([
    ['pending', 'Queued for WhatsApp'],
    ['accepted', 'Awaiting WhatsApp confirmation'],
    ['unknown', 'WhatsApp send not confirmed'],
  ])(
    'explains the %s transport state without claiming a send',
    (outcome, label) => {
      useMessageContext().contentAttributes.value = {
        jrcBrokerOutbound: { version: 1, state: 'PENDING' },
        jrcBrokerDelivery: { version: 1, outcome },
      };
      expect(
        shallowMount(MessageMeta)
          .findComponent(MessageStatus)
          .props('statusLabel')
      ).toBe(label);
    }
  );

  it.each(['pending', 'accepted', 'unknown'])(
    'keeps a %s callback pending without provider confirmation',
    outcome => {
      useMessageContext().contentAttributes.value = {
        jrcBrokerOutbound: { version: 1, state: 'PENDING' },
        jrcBrokerDelivery: { version: 1, outcome },
      };
      const wrapper = shallowMount(MessageMeta);
      expect(wrapper.findComponent(MessageStatus).props('status')).toBe(
        'progress'
      );
    }
  );

  it('does not treat a canonical ID alone as provider confirmation', () => {
    useMessageContext().contentAttributes.value = {
      jrcBrokerOutbound: {
        version: 1,
        state: 'SENT',
        canonicalMessageId: 'synthetic-canonical-id',
      },
    };
    expect(
      shallowMount(MessageMeta).findComponent(MessageStatus).props('status')
    ).toBe('progress');
  });

  it.each(['sent', 'delivered', 'read'])(
    'shows the provider-confirmed %s state',
    status => {
      useMessageContext().status.value = status;
      useMessageContext().contentAttributes.value = {
        jrcBrokerOutbound: {
          version: 1,
          state: status.toUpperCase(),
          canonicalMessageId: 'synthetic-id',
          providerMessageId: 'synthetic-provider',
        },
      };
      expect(
        shallowMount(MessageMeta).findComponent(MessageStatus).props('status')
      ).toBe(status);
    }
  );

  it('preserves generic API inbox behavior without Broker metadata', () => {
    expect(
      shallowMount(MessageMeta).findComponent(MessageStatus).props('status')
    ).toBe('sent');
  });
});
