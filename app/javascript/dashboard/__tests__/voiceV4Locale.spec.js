import { describe, expect, it } from 'vitest';
import ptBR from '../i18n/locale/pt_BR';
describe('Portuguese voice workspace', () => {
  it('loads the existing Portuguese Contact Center labels in the pt_BR locale without relying on English fallback', () => {
    expect(ptBR.JRC_CONTACT_CENTER?.INBOX_360?.CUSTOMER).toBe('Cliente');
    expect(ptBR.JRC_CONTACT_CENTER?.INBOX_360?.CONVERSATION).toBeTruthy();
    expect(ptBR.JRC_CONTACT_CENTER?.AGENT?.PAUSE_REASONS?.lunch).toBe('Almoço');
    expect(ptBR.VOICE_V4?.NO_ACTIVE_CALL).toBe('Nenhuma ligação ativa');
  });
});
