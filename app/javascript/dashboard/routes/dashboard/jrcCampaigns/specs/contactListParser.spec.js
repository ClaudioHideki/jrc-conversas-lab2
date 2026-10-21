import { describe, expect, it } from 'vitest';
import { parseContactList } from '../contactListParser';

describe('contact list parsing preserves destinations', () => {
  it.each([',', ';', '\t'])(
    'reads %j CSV with headers, BOM, escaped quotes and quoted separators',
    separator => {
      const csv = `\uFEFFnome${separator}telefone${separator}email\r\n"QA${separator} ""Contato"""${separator}+5511999999000${separator}qa@example.test`;
      expect(parseContactList(csv)).toEqual([
        {
          name: `QA${separator} "Contato"`,
          phone: '+5511999999000',
          email: 'qa@example.test',
        },
      ]);
    }
  );
  it('preserves newlines inside a quoted name without shifting phone or email', () => {
    expect(
      parseContactList(
        'name,phone,email\n"QA\nContact",+5511999999000,qa@example.test'
      )
    ).toEqual([
      {
        name: 'QA\nContact',
        phone: '+5511999999000',
        email: 'qa@example.test',
      },
    ]);
  });
  it('accepts plain one-column phones and emails and ignores empty lines', () => {
    expect(parseContactList('\n+5511999999000\nqa@example.test\n\n')).toEqual([
      { phone: '+5511999999000' },
      { email: 'qa@example.test' },
    ]);
  });
  it('retains both destinations in a headerless phone/email pair', () => {
    expect(parseContactList('+5511999999000,qa@example.test')).toEqual([
      { phone: '+5511999999000', email: 'qa@example.test' },
    ]);
  });
  it.each([
    'name,phone\n"QA,+5511999999000',
    'name,phone\n"QA"broken,+5511999999000',
  ])(
    'rejects malformed CSV instead of silently moving destinations: %s',
    csv => {
      expect(() => parseContactList(csv)).toThrow('invalid_csv');
    }
  );
});
