import {
  INBOX_TYPES,
  VOICE_CALL_PROVIDERS,
  getInboxClassByType,
  getInboxChannelKey,
  getInboxIconByType,
  getInboxVoiceIcon,
  getInboxWarningIconClass,
  getVoiceCallIcon,
  isWhatsAppInbox,
} from '../inbox';

describe('#Inbox Helpers', () => {
  describe('isWhatsAppInbox', () => {
    it('recognizes native and Twilio WhatsApp inboxes', () => {
      expect(isWhatsAppInbox({ channelType: INBOX_TYPES.WHATSAPP })).toBe(true);
      expect(
        isWhatsAppInbox({
          channelType: INBOX_TYPES.TWILIO,
          medium: 'whatsapp',
        })
      ).toBe(true);
    });

    it('recognizes Evolution API inboxes by explicit metadata', () => {
      expect(
        isWhatsAppInbox({
          channel_type: INBOX_TYPES.API,
          additional_attributes: { provider: 'evolution' },
        })
      ).toBe(true);
    });

    it.each([
      { channel_type: INBOX_TYPES.API, jrc_broker_bound: true },
      {
        channel_type: INBOX_TYPES.API,
        jrc_broker_bound: true,
        additional_attributes: {},
      },
      { channelType: INBOX_TYPES.API, jrcBrokerBound: true },
      {
        channelType: INBOX_TYPES.API,
        jrcBrokerBound: true,
        additionalAttributes: {},
      },
    ])(
      'recognizes a Broker-bound Gestor inbox without name or provider hints: %j',
      inbox => {
        const gestor = { id: 13, name: 'Gestor', ...inbox };

        expect(isWhatsAppInbox(gestor)).toBe(true);
        expect(getInboxChannelKey(gestor)).toBe('whatsapp');
      }
    );

    it.each([false, 'false', 'true', 0, 1, null, undefined])(
      'requires a boolean true Broker binding for WhatsApp grouping: %j',
      bound => {
        [{ jrc_broker_bound: bound }, { jrcBrokerBound: bound }].forEach(
          flags => {
            const inbox = {
              channel_type: INBOX_TYPES.API,
              name: 'Gestor',
              additional_attributes: {},
              ...flags,
            };

            expect(isWhatsAppInbox(inbox)).toBe(false);
            expect(getInboxChannelKey(inbox)).toBe('api');
          }
        );
      }
    );

    it('does not treat editable attributes as a Broker binding', () => {
      const inbox = {
        channel_type: INBOX_TYPES.API,
        name: 'Gestor',
        additional_attributes: { jrc_broker_bound: true },
      };

      expect(isWhatsAppInbox(inbox)).toBe(false);
      expect(getInboxChannelKey(inbox)).toBe('api');
    });

    it.each([
      [INBOX_TYPES.EMAIL, 'email'],
      [INBOX_TYPES.INSTAGRAM, 'instagram'],
      [INBOX_TYPES.FB, 'facebook'],
      [INBOX_TYPES.WEB, 'website'],
      [INBOX_TYPES.TELEGRAM, 'telegram'],
      [INBOX_TYPES.SMS, 'sms'],
      [INBOX_TYPES.TWILIO, 'sms'],
    ])(
      'preserves the native %s channel with a Broker-shaped flag',
      (channelType, expected) => {
        const inbox = { channelType, name: 'Gestor', jrc_broker_bound: true };

        expect(isWhatsAppInbox(inbox)).toBe(false);
        expect(getInboxChannelKey(inbox)).toBe(expected);
      }
    );

    it('recomputes the binding after switching Accounts with the same inbox ID', () => {
      const views = [
        { account_id: 1, jrc_broker_bound: true },
        { account_id: 2 },
        { accountId: 2, jrcBrokerBound: true },
        { account_id: 1, jrc_broker_bound: false },
      ];

      expect(
        views.map(view =>
          getInboxChannelKey({
            id: 13,
            channel_type: INBOX_TYPES.API,
            name: 'Gestor',
            ...view,
          })
        )
      ).toEqual(['whatsapp', 'api', 'whatsapp', 'api']);
    });

    it('recognizes the existing API inbox by its WhatsApp name', () => {
      expect(
        isWhatsAppInbox({
          channelType: INBOX_TYPES.API,
          name: 'WhatsApp Homologa',
        })
      ).toBe(true);
    });

    it('does not classify generic API inboxes as WhatsApp', () => {
      expect(
        isWhatsAppInbox({
          channelType: INBOX_TYPES.API,
          name: 'Integração CRM',
        })
      ).toBe(false);
    });
  });

  describe('getInboxChannelKey', () => {
    it('groups API WhatsApp inboxes under WhatsApp', () => {
      expect(
        getInboxChannelKey({
          channelType: INBOX_TYPES.API,
          name: 'WhatsApp Homologa',
        })
      ).toBe('whatsapp');
    });

    it('maps configured native channels to their presentation key', () => {
      expect(getInboxChannelKey({ channelType: INBOX_TYPES.EMAIL })).toBe(
        'email'
      );
      expect(getInboxChannelKey({ channelType: INBOX_TYPES.INSTAGRAM })).toBe(
        'instagram'
      );
    });

    it('keeps a generic API inbox as API', () => {
      expect(
        getInboxChannelKey({
          channelType: INBOX_TYPES.API,
          name: 'Integração CRM',
        })
      ).toBe('api');
    });
  });

  describe('getInboxClassByType', () => {
    it('should return correct class for web widget', () => {
      expect(getInboxClassByType('Channel::WebWidget')).toEqual(
        'globe-desktop'
      );
    });
    it('should return correct class for fb page', () => {
      expect(getInboxClassByType('Channel::FacebookPage')).toEqual(
        'brand-facebook'
      );
    });
    it('should return correct class for  twitter profile', () => {
      expect(getInboxClassByType('Channel::TwitterProfile')).toEqual(
        'brand-twitter'
      );
    });
    it('should return correct class for twilio sms', () => {
      expect(getInboxClassByType('Channel::TwilioSms', '')).toEqual(
        'brand-sms'
      );
    });
    it('should return correct class for whatsapp', () => {
      expect(getInboxClassByType('Channel::TwilioSms', 'whatsapp')).toEqual(
        'brand-whatsapp'
      );
    });
    it('should return correct class for Api', () => {
      expect(getInboxClassByType('Channel::Api')).toEqual('cloud');
    });
    it('should return correct class for Email', () => {
      expect(getInboxClassByType('Channel::Email')).toEqual('mail');
    });
    it('should return correct class for TikTok', () => {
      expect(getInboxClassByType(INBOX_TYPES.TIKTOK)).toEqual('brand-tiktok');
    });
  });

  describe('getInboxIconByType', () => {
    describe('fill variant (default)', () => {
      it('returns correct icon for web widget', () => {
        expect(getInboxIconByType(INBOX_TYPES.WEB)).toBe('i-ri-global-fill');
      });

      it('returns correct icon for Facebook', () => {
        expect(getInboxIconByType(INBOX_TYPES.FB)).toBe('i-ri-messenger-fill');
      });

      it('returns correct icon for Twitter', () => {
        expect(getInboxIconByType(INBOX_TYPES.TWITTER)).toBe(
          'i-ri-twitter-x-fill'
        );
      });

      it('returns correct icon for WhatsApp', () => {
        expect(getInboxIconByType(INBOX_TYPES.WHATSAPP)).toBe(
          'i-ri-whatsapp-fill'
        );
      });

      it('returns correct icon for API', () => {
        expect(getInboxIconByType(INBOX_TYPES.API)).toBe('i-ri-cloudy-fill');
      });

      it('returns correct icon for Email', () => {
        expect(getInboxIconByType(INBOX_TYPES.EMAIL)).toBe('i-ri-mail-fill');
      });

      it('returns correct icon for Telegram', () => {
        expect(getInboxIconByType(INBOX_TYPES.TELEGRAM)).toBe(
          'i-ri-telegram-fill'
        );
      });

      it('returns correct icon for Line', () => {
        expect(getInboxIconByType(INBOX_TYPES.LINE)).toBe('i-ri-line-fill');
      });

      it('returns correct icon for TikTok', () => {
        expect(getInboxIconByType(INBOX_TYPES.TIKTOK)).toBe('i-ri-tiktok-fill');
      });

      it('returns default icon for unknown type', () => {
        expect(getInboxIconByType('UNKNOWN_TYPE')).toBe('i-ri-chat-1-fill');
      });

      it('returns default icon for undefined type', () => {
        expect(getInboxIconByType(undefined)).toBe('i-ri-chat-1-fill');
      });
    });

    describe('line variant', () => {
      it('returns correct line icon for web widget', () => {
        expect(getInboxIconByType(INBOX_TYPES.WEB, null, 'line')).toBe(
          'i-woot-website'
        );
      });

      it('returns correct line icon for Facebook', () => {
        expect(getInboxIconByType(INBOX_TYPES.FB, null, 'line')).toBe(
          'i-woot-messenger'
        );
      });

      it('returns correct line icon for TikTok', () => {
        expect(getInboxIconByType(INBOX_TYPES.TIKTOK, null, 'line')).toBe(
          'i-woot-tiktok'
        );
      });

      it('returns correct line icon for unknown type', () => {
        expect(getInboxIconByType('UNKNOWN_TYPE', null, 'line')).toBe(
          'i-ri-chat-1-line'
        );
      });
    });

    describe('Twilio cases', () => {
      describe('fill variant', () => {
        it('returns WhatsApp icon for Twilio WhatsApp number', () => {
          expect(getInboxIconByType(INBOX_TYPES.TWILIO, 'whatsapp')).toBe(
            'i-ri-whatsapp-fill'
          );
        });

        it('returns SMS icon for regular Twilio number', () => {
          expect(getInboxIconByType(INBOX_TYPES.TWILIO, 'sms')).toBe(
            'i-ri-chat-1-fill'
          );
        });

        it('returns SMS icon when phone number is undefined', () => {
          expect(getInboxIconByType(INBOX_TYPES.TWILIO, undefined)).toBe(
            'i-ri-chat-1-fill'
          );
        });
      });

      describe('line variant', () => {
        it('returns WhatsApp line icon for Twilio WhatsApp number', () => {
          expect(
            getInboxIconByType(INBOX_TYPES.TWILIO, 'whatsapp', 'line')
          ).toBe('i-woot-whatsapp');
        });

        it('returns SMS line icon for regular Twilio number', () => {
          expect(getInboxIconByType(INBOX_TYPES.TWILIO, 'sms', 'line')).toBe(
            'i-ri-chat-1-line'
          );
        });
      });
    });
  });

  describe('getInboxWarningIconClass', () => {
    it('should return correct class for warning', () => {
      expect(getInboxWarningIconClass('Channel::FacebookPage', true)).toEqual(
        'warning'
      );
    });
  });

  describe('getVoiceCallIcon', () => {
    it('returns the WhatsApp voice glyph for the whatsapp provider', () => {
      expect(getVoiceCallIcon(VOICE_CALL_PROVIDERS.WHATSAPP)).toBe(
        'i-woot-whatsapp-voice'
      );
    });

    it('returns the generic voice-call glyph for the twilio provider', () => {
      expect(getVoiceCallIcon(VOICE_CALL_PROVIDERS.TWILIO)).toBe(
        'i-woot-voice-call'
      );
    });

    it('falls back to the generic voice-call glyph for an unknown provider', () => {
      expect(getVoiceCallIcon('unknown')).toBe('i-woot-voice-call');
      expect(getVoiceCallIcon(undefined)).toBe('i-woot-voice-call');
    });
  });

  describe('getInboxVoiceIcon', () => {
    it('returns the WhatsApp voice glyph for a WhatsApp inbox', () => {
      expect(getInboxVoiceIcon(INBOX_TYPES.WHATSAPP)).toBe(
        'i-woot-whatsapp-voice'
      );
    });

    it('returns the WhatsApp voice glyph for a Twilio WhatsApp inbox', () => {
      expect(getInboxVoiceIcon(INBOX_TYPES.TWILIO, 'whatsapp')).toBe(
        'i-woot-whatsapp-voice'
      );
    });

    it('returns the generic voice-call glyph for a Twilio voice inbox', () => {
      expect(getInboxVoiceIcon(INBOX_TYPES.TWILIO, 'sms')).toBe(
        'i-woot-voice-call'
      );
    });
  });

  describe('getInboxIconByType with voice enabled', () => {
    it('returns the WhatsApp voice glyph for a voice-enabled WhatsApp inbox', () => {
      expect(
        getInboxIconByType(INBOX_TYPES.WHATSAPP, undefined, 'line', true)
      ).toBe('i-woot-whatsapp-voice');
    });

    it('returns the generic voice-call glyph for a voice-enabled Twilio inbox', () => {
      expect(getInboxIconByType(INBOX_TYPES.TWILIO, 'sms', 'line', true)).toBe(
        'i-woot-voice-call'
      );
    });

    it('returns the normal channel icon when voice is not enabled', () => {
      expect(
        getInboxIconByType(INBOX_TYPES.WHATSAPP, undefined, 'line', false)
      ).toBe('i-woot-whatsapp');
    });
  });
});
