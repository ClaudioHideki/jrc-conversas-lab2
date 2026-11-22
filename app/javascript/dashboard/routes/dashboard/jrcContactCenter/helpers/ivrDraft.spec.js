import { describe, expect, it } from 'vitest';
import {
  parseIvrDraft,
  emptyIvr,
  addIvrNode,
  removeIvrNode,
  clearIvrQueues,
  clearIvrAudioReferences,
  setIvrAudioReference,
} from './ivrDraft';

describe('safe local IVR editing, without a provider contract', () => {
  const valid = () => ({
    schema_version: 1,
    start: 'end',
    nodes: [{ id: 'end', type: 'end' }],
  });
  it('accepts a supported local document without changing its fields', () => {
    const graph = valid();
    expect(parseIvrDraft(JSON.stringify(graph))).toEqual(graph);
  });
  it.each([
    'null',
    'false',
    '[]',
    '{}',
    '{',
    JSON.stringify({ ...valid(), schema_version: 4 }),
  ])('rejects malformed or unsupported import %s', value => {
    expect(() => parseIvrDraft(value)).toThrow();
  });
  it('rejects repeated IDs and unsafe control characters before rendering editable nodes', () => {
    const graph = valid();
    graph.nodes.push({ id: 'end', type: 'end' });
    expect(() => parseIvrDraft(JSON.stringify(graph))).toThrow();
    graph.nodes = [{ id: 'end\n', type: 'end' }];
    expect(() => parseIvrDraft(JSON.stringify(graph))).toThrow();
  });
  it('rejects executable/provider nodes and structurally malformed menu options', () => {
    const graph = valid();
    graph.nodes[0].type = 'provider_command';
    expect(() => parseIvrDraft(JSON.stringify(graph))).toThrow();
    graph.nodes[0] = { id: 'menu', type: 'menu', options: [null] };
    expect(() => parseIvrDraft(JSON.stringify(graph))).toThrow();
  });
  it('does not create an operational time, attempt count, destination or entry choice for the user', () => {
    const graph = emptyIvr();
    addIvrNode(graph, 'menu');
    addIvrNode(graph, 'queue');
    expect(graph.start).toBe('');
    expect(graph.nodes[0]).toMatchObject({
      timeout_seconds: '',
      max_attempts: '',
      options: [],
      on_timeout: '',
      on_invalid: '',
    });
    expect(graph.nodes[1].queue_id).toBe('');
  });
  it('clears references to a removed node without inventing replacement destinations', () => {
    const graph = {
      schema_version: 1,
      start: 'target',
      nodes: [
        {
          id: 'menu',
          type: 'menu',
          options: [{ digit: '1', target: 'target' }],
          on_timeout: 'target',
          on_invalid: 'menu',
        },
        { id: 'target', type: 'end' },
      ],
    };
    removeIvrNode(graph, 'target');
    expect(graph.start).toBe('');
    expect(graph.nodes[0]).toMatchObject({
      options: [{ digit: '1', target: '' }],
      on_timeout: '',
      on_invalid: 'menu',
    });
  });
  it('requires explicit queue reselection when a new draft changes unit', () => {
    const graph = {
      ...valid(),
      nodes: [
        { id: 'route', type: 'queue', queue_id: '77' },
        { id: 'end', type: 'end' },
      ],
    };
    clearIvrQueues(graph);
    expect(graph.nodes[0].queue_id).toBe('');
    expect(graph.nodes[1]).toEqual({ id: 'end', type: 'end' });
  });
  it('refuses an oversized import without evaluating it', () => {
    expect(() => parseIvrDraft(' '.repeat(1048577))).toThrow();
  });
});

describe('safe exact audio references in internal IVR schema two', () => {
  const reference = () => ({
    asset_id: '9007199254740993',
    version_id: '22',
    sha256: 'a'.repeat(64),
  });
  const graph = () => ({
    schema_version: 2,
    start: 'menu',
    nodes: [
      { id: 'menu', type: 'menu', options: [], audio_reference: reference() },
      { id: 'end', type: 'end' },
    ],
  });
  it('round-trips exact bigint strings and immutable version hashes without rounding', () => {
    expect(parseIvrDraft(JSON.stringify(graph()))).toEqual(graph());
  });
  it('does not reinterpret a legacy schema one graph containing unknown audio data', () => {
    const value = graph();
    value.schema_version = 1;
    expect(() => parseIvrDraft(JSON.stringify(value))).toThrow();
  });
  it.each([
    null,
    false,
    [],
    '',
    {},
    { ...reference(), asset_id: 11 },
    { ...reference(), version_id: '01' },
    { ...reference(), asset_id: '9223372036854775808' },
    { ...reference(), sha256: 'A'.repeat(64) },
    { ...reference(), sha256: 'a'.repeat(64) + '\n' },
    { ...reference(), account_id: '1' },
    { ...reference(), blob_id: '1' },
  ])(
    'rejects malformed or authority-bearing local references %j before editor hydration',
    value => {
      const invalid = graph();
      invalid.nodes[0].audio_reference = value;
      expect(() => parseIvrDraft(JSON.stringify(invalid))).toThrow();
    }
  );
  it('promotes only explicit selections and clears unit references without removing the menu', () => {
    const value = graph();
    value.schema_version = 1;
    delete value.nodes[0].audio_reference;
    setIvrAudioReference(value, 0, reference());
    expect(value.schema_version).toBe(2);
    expect(value.nodes[0].audio_reference).toEqual(reference());
    clearIvrAudioReferences(value);
    expect(value.nodes[0]).toEqual({ id: 'menu', type: 'menu', options: [] });
    expect(value.schema_version).toBe(2);
    setIvrAudioReference(value, 0, reference());
    setIvrAudioReference(value, 0, null);
    expect(value.nodes[0]).not.toHaveProperty('audio_reference');
    expect(() => setIvrAudioReference(value, 1, reference())).toThrow();
  });
  it('cannot attach menu audio to a terminal node', () => {
    const invalid = graph();
    invalid.nodes[1].audio_reference = reference();
    expect(() => parseIvrDraft(JSON.stringify(invalid))).toThrow();
  });
});
