import { validCalendarDefinition } from 'dashboard/routes/dashboard/jrcContactCenter/helpers/calendarForm';

const record = value =>
  value && typeof value === 'object' && !Array.isArray(value);
const digest = value =>
  typeof value === 'string' &&
  /^[0-9a-f]{64}$/.test(value) &&
  !/[^0-9a-f]/.test(value);
const uuid = value =>
  typeof value === 'string' &&
  value.length === 36 &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(
    value
  );

// This checks safe editing shape only. Every save/preview still requires fresh native authorization and source attestation.
export const validIvrCalendarSnapshot = item =>
  record(item) &&
  Object.keys(item).sort().join(',') === 'active,definition,id' &&
  uuid(item.id) &&
  [true, false].includes(item.active) &&
  validCalendarDefinition(item.definition);

export const validIvrCalendarReference = value =>
  record(value) &&
  Object.keys(value).sort().join(',') ===
    'calendar_id,sha256,snapshot,unit_revision' &&
  uuid(value.calendar_id) &&
  digest(value.sha256) &&
  digest(value.unit_revision) &&
  validIvrCalendarSnapshot(value.snapshot) &&
  value.snapshot.id === value.calendar_id;

export const validIvrCalendarNode = node =>
  node.type === 'calendar' &&
  typeof node.on_open === 'string' &&
  typeof node.on_closed === 'string' &&
  (node.calendar_reference === null ||
    validIvrCalendarReference(node.calendar_reference));

export const setIvrCalendarReference = (graph, index, value) => {
  if (
    graph.nodes[index]?.type !== 'calendar' ||
    (value !== null && !validIvrCalendarReference(value))
  )
    throw new Error('invalid_ivr_graph');
  graph.schema_version = 3;
  graph.nodes[index].calendar_reference =
    value === null ? null : JSON.parse(JSON.stringify(value));
};

export const clearIvrCalendarReferences = graph => {
  graph.nodes
    .filter(node => node.type === 'calendar')
    .forEach(node => {
      node.calendar_reference = null;
    });
};
