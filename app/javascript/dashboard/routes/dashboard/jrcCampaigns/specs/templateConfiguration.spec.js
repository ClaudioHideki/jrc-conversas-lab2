import {
  variables,
  templateParts,
  templateErrors,
  parseTemplateJson,
} from '../templateConfiguration';

const template = {
  status: 'APPROVED',
  components: [
    { type: 'HEADER', format: 'IMAGE' },
    { type: 'BODY', text: 'Hello {{1}}' },
    { type: 'FOOTER', text: 'Footer' },
    {
      type: 'BUTTONS',
      buttons: [
        { type: 'URL', text: 'Open', url: 'https://example.test/{{1}}' },
      ],
    },
  ],
};
const params = () => ({
  processed_params: {
    header: { media_type: 'image', media_asset_id: 7 },
    body: { 1: 'Ana' },
    buttons: [{ type: 'url', parameter: 'order' }],
  },
});

describe('Meta campaign template configuration', () => {
  it('discovers every component and variable', () => {
    expect(variables('{{1}} {{name}} {{1}}')).toEqual(['1', 'name']);
    expect(templateParts(template).footer.text).toBe('Footer');
    expect(templateErrors(template, params())).toEqual([]);
  });
  it('blocks missing media, body and dynamic button parameters', () => {
    expect(templateErrors(template, {})).toEqual([
      'MEDIA',
      'body:1',
      'button:0',
    ]);
  });
  it.each(['{bad', '[]', 'null', '"text"'])(
    'rejects invalid advanced JSON %s',
    value => {
      expect(() => parseTemplateJson(value)).toThrow();
    }
  );
  it.each(['VIDEO', 'DOCUMENT'])('supports a retained %s header', format => {
    const input = {
      status: 'APPROVED',
      components: [{ type: 'HEADER', format }],
    };
    expect(
      templateErrors(input, {
        processed_params: {
          header: { media_type: format.toLowerCase(), media_asset_id: 1 },
        },
      })
    ).toEqual([]);
  });
  it.each(['header', 'buttons'])(
    'blocks an absent %s component in advanced JSON',
    key => {
      const definition = {
        status: 'APPROVED',
        components: [{ type: 'BODY', text: 'Hello' }],
      };
      expect(
        templateErrors(definition, {
          processed_params: { [key]: { unexpected: 'value' } },
        })
      ).toContain('JSON');
    }
  );
  it('blocks unsupported components and paused templates', () => {
    expect(
      templateErrors({ ...template, components: [{ type: 'CAROUSEL' }] }, {})
    ).toContain('UNSUPPORTED');
    expect(templateErrors({ ...template, status: 'PAUSED' }, params())).toEqual(
      ['TEMPLATE']
    );
  });
});
