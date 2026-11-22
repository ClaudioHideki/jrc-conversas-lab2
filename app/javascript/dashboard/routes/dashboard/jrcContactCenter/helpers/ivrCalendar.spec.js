import { describe, it, expect } from 'vitest';
import {
  validIvrCalendarReference,
  setIvrCalendarReference,
  clearIvrCalendarReferences,
} from 'dashboard/routes/dashboard/jrcContactCenter/helpers/ivrCalendar';
import {
  emptyIvr,
  addIvrNode,
  removeIvrNode,
  parseIvrDraft,
  setIvrAudioReference,
} from 'dashboard/routes/dashboard/jrcContactCenter/helpers/ivrDraft';
import { newCalendarDefinition } from 'dashboard/routes/dashboard/jrcContactCenter/helpers/calendarForm';

const reference = () => {
  const definition = {
    ...newCalendarDefinition('America/Sao_Paulo'),
    name: 'SYNTHETIC calendar',
  };
  definition.weekly['1'] = [['08:00', '12:00']];
  const id = '11111111-1111-4111-8111-111111111111';
  return {
    calendar_id: id,
    unit_revision: 'a'.repeat(64),
    sha256: 'b'.repeat(64),
    snapshot: { id, active: true, definition },
  };
};

describe('safe local URA calendar editing with synthetic values; not native authorization proof', () => {
  it('accepts schema3 with ordinary terminal nodes while leaving unknown future schemas rejected', () => {
    const graph = {
      schema_version: 3,
      start: 'end',
      nodes: [{ id: 'end', type: 'end' }],
    };
    expect(parseIvrDraft(JSON.stringify(graph))).toEqual(graph);
    expect(() =>
      parseIvrDraft(JSON.stringify({ ...graph, schema_version: 4 }))
    ).toThrow('invalid_ivr_graph');
  });
  it('adds a calendar node without silently inventing a pin or branch destinations', () => {
    const graph = emptyIvr();
    addIvrNode(graph, 'calendar');
    expect(graph.schema_version).toBe(3);
    expect(graph.nodes[0]).toMatchObject({
      type: 'calendar',
      calendar_reference: null,
      on_open: '',
      on_closed: '',
    });
    expect(parseIvrDraft(JSON.stringify(graph))).toEqual(graph);
  });

  it('never downgrades a calendar graph when a menu receives an audio reference', () => {
    const graph = emptyIvr();
    addIvrNode(graph, 'calendar');
    addIvrNode(graph, 'menu');
    setIvrCalendarReference(graph, 0, reference());
    setIvrAudioReference(graph, 1, {
      asset_id: '5',
      version_id: '6',
      sha256: 'c'.repeat(64),
    });
    expect(graph.schema_version).toBe(3);
    expect(parseIvrDraft(JSON.stringify(graph))).toEqual(graph);
  });

  it('copies the reviewed wire value so subsequent picker changes cannot mutate the graph snapshot', () => {
    const graph = emptyIvr();
    addIvrNode(graph, 'calendar');
    const proposed = reference();
    setIvrCalendarReference(graph, 0, proposed);
    proposed.snapshot.definition.name = 'SYNTHETIC later picker edit';
    expect(graph.nodes[0].calendar_reference.snapshot.definition.name).toBe(
      'SYNTHETIC calendar'
    );
  });

  it.each([
    'snapshot-id',
    'digest',
    'scope-claim',
    'active-string',
    'invalid-definition',
  ])('rejects malformed %s reference shape before any native request', kind => {
    const value = reference();
    if (kind === 'snapshot-id')
      value.snapshot.id = '22222222-2222-4222-8222-222222222222';
    if (kind === 'digest') value.sha256 = 'not-a-digest';
    if (kind === 'scope-claim') value.account_id = '999';
    if (kind === 'active-string') value.snapshot.active = 'true';
    if (kind === 'invalid-definition')
      value.snapshot.definition.weekly['1'] = [['12:00', '08:00']];
    expect(validIvrCalendarReference(value)).toBe(false);
  });

  it('clears both calendar branch references when their destination is removed', () => {
    const graph = emptyIvr();
    addIvrNode(graph, 'calendar');
    addIvrNode(graph, 'end');
    graph.nodes[0].on_open = graph.nodes[1].id;
    graph.nodes[0].on_closed = graph.nodes[1].id;
    removeIvrNode(graph, graph.nodes[1].id);
    expect(graph.nodes[0].on_open).toBe('');
    expect(graph.nodes[0].on_closed).toBe('');
  });

  it('removes private calendar snapshots on a unit change while preserving editable graph structure', () => {
    const graph = emptyIvr();
    addIvrNode(graph, 'calendar');
    setIvrCalendarReference(graph, 0, reference());
    clearIvrCalendarReferences(graph);
    expect(graph.nodes[0].calendar_reference).toBeNull();
    expect(graph.nodes[0].type).toBe('calendar');
    expect(graph.schema_version).toBe(3);
  });

  it.each([1, 2])(
    'refuses a calendar node smuggled into legacy graph schema%s',
    version => {
      const graph = emptyIvr();
      addIvrNode(graph, 'calendar');
      graph.schema_version = version;
      expect(() => parseIvrDraft(JSON.stringify(graph))).toThrow(
        'invalid_ivr_graph'
      );
    }
  );
});
