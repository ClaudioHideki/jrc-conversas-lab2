import { describe, expect, it } from 'vitest';
import {
  parseIvrDraft,
  emptyIvr,
  addIvrNode,
  removeIvrNode,
  clearIvrQueues,
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
    JSON.stringify({ ...valid(), schema_version: 2 }),
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
