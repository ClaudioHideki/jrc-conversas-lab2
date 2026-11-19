import { beforeEach, describe, expect, it } from 'vitest';
import { acwFormAnswers, acwFormDefinition } from './acwForms';

let definition;
let answers;
beforeEach(() => {
  definition = {
    fields: [
      {
        key: 'detail',
        label: 'SYNTHETIC detail',
        type: 'text',
        required: true,
      },
      {
        key: 'count',
        label: 'SYNTHETIC count',
        type: 'integer',
        required: true,
      },
      {
        key: 'confirmed',
        label: 'SYNTHETIC confirmation',
        type: 'boolean',
        required: true,
      },
      {
        key: 'result',
        label: 'SYNTHETIC choice',
        type: 'select',
        required: true,
        options: ['first', 'second'],
      },
    ],
  };
  answers = {
    detail: 'SYNTHETIC private text',
    count: 0,
    confirmed: false,
    result: 'first',
  };
});

describe('ACW values reuse native catalogue validators without Service Desk authorization', () => {
  it('copies all four native field types without retaining mutable choice arrays', () => {
    const result = acwFormDefinition(definition);
    expect(result).toEqual(definition);
    result.fields[3].options.push('SYNTHETIC changed');
    expect(definition.fields[3].options).toEqual(['first', 'second']);
  });
  it('accepts explicit false and zero as required answers without rewriting text', () => {
    expect(acwFormAnswers(definition, answers, { complete: true })).toEqual(
      answers
    );
  });
  it('allows missing draft values while preserving the required definition', () => {
    expect(acwFormAnswers(definition, {}, { complete: false })).toEqual({});
    expect(definition.fields.every(field => field.required)).toBe(true);
  });
  it('does not accept inherited values as answers for a field with an Object prototype name', () => {
    definition.fields = [
      {
        key: 'toString',
        label: 'SYNTHETIC own text',
        type: 'text',
        required: false,
      },
    ];
    expect(acwFormAnswers(definition, {}, { complete: true })).toEqual({});
    expect(
      acwFormAnswers(
        definition,
        Object.create({ toString: 'SYNTHETIC inherited' }),
        { complete: true }
      )
    ).toEqual({});
    definition.fields[0].required = true;
    expect(() => acwFormAnswers(definition, {}, { complete: true })).toThrow();
  });
  it.each(['detail', 'count', 'confirmed', 'result'])(
    'rejects completion missing required %s',
    key => {
      delete answers[key];
      expect(() =>
        acwFormAnswers(definition, answers, { complete: true })
      ).toThrow();
    }
  );
  it.each([null, '', '   '])(
    'rejects completion with empty required text %s',
    value => {
      answers.detail = value;
      expect(() =>
        acwFormAnswers(definition, answers, { complete: true })
      ).toThrow();
    }
  );
  it.each([
    ['detail', {}],
    ['detail', 'x'.repeat(4001)],
    ['count', 1.5],
    ['count', 2 ** 53],
    ['confirmed', 'false'],
    ['result', 'unknown'],
  ])('does not accept invalid typed draft field %s case %#', (key, value) => {
    answers[key] = value;
    expect(() =>
      acwFormAnswers(definition, answers, { complete: false })
    ).toThrow();
  });
  it.each(['account_id', 'unit_id', '__proto__', 'constructor'])(
    'rejects unknown answer key %s',
    key => {
      answers = { ...answers, [key]: 'SYNTHETIC private value' };
      expect(() =>
        acwFormAnswers(definition, answers, { complete: false })
      ).toThrow();
    }
  );
  it.each(
    [null, [], {}, { fields: [] }, { fields: [], account_id: '1' }].map(
      value => ({ value })
    )
  )('rejects malformed definition %#', ({ value }) => {
    expect(() => acwFormDefinition(value)).toThrow();
  });
  it.each(['__proto__', 'constructor', 'prototype'])(
    'preserves native reserved key %s rejection',
    key => {
      definition.fields[0].key = key;
      expect(() => acwFormDefinition(definition)).toThrow();
    }
  );
  it('rejects duplicate fields, blank labels and hidden options payloads', () => {
    definition.fields[1].key = 'detail';
    expect(() => acwFormDefinition(definition)).toThrow();
    definition.fields[1].key = 'count';
    definition.fields[0].label = ' ';
    expect(() => acwFormDefinition(definition)).toThrow();
    definition.fields[0].label = 'SYNTHETIC detail';
    definition.fields[0].options = {};
    expect(() => acwFormDefinition(definition)).toThrow();
  });
  it.each([
    { options: ['first', 'first'] },
    { options: ['first', ' '] },
    { options: Array.from({ length: 101 }, (_, i) => String(i)) },
  ])('rejects invalid select options %#', ({ options }) => {
    definition.fields[3].options = options;
    expect(() => acwFormDefinition(definition)).toThrow();
  });
  it('bounds the serialized multibyte answers before accepting a draft', () => {
    definition.fields = Array.from({ length: 50 }, (_, i) => ({
      ...definition.fields[0],
      key: `field-${i}`,
    }));
    answers = Object.fromEntries(
      definition.fields.map(field => [field.key, 'á'.repeat(4000)])
    );
    expect(() =>
      acwFormAnswers(definition, answers, { complete: false })
    ).toThrow();
  });
  it.each(['label', 'option', 'answer'])(
    'rejects NUL in %s before persistence',
    part => {
      const value = `SYNTHETIC${String.fromCharCode(0)}private`;
      if (part === 'answer') {
        answers.detail = value;
        expect(() =>
          acwFormAnswers(definition, answers, { complete: false })
        ).toThrow();
      } else {
        if (part === 'label') definition.fields[0].label = value;
        else definition.fields[3].options = [value];
        expect(() => acwFormDefinition(definition)).toThrow();
      }
    }
  );
  it('never coerces the completion flag to skip required fields', () => {
    expect(() =>
      acwFormAnswers(definition, {}, { complete: 'false' })
    ).toThrow();
  });
});
