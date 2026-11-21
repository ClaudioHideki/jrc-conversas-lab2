export const IVR_BYTES_LIMIT = 1048576;
export const IVR_NODES_LIMIT = 128;
export const emptyIvr = () => ({ schema_version: 1, start: '', nodes: [] });
const plainRecord = value =>
  value && typeof value === 'object' && !Array.isArray(value);

export const validIvrAudioReference = value => {
  const id = input =>
    typeof input === 'string' &&
    /^[1-9][0-9]{0,18}$/.test(input) &&
    !/[^0-9]/.test(input) &&
    (input.length < 19 || input <= '9223372036854775807');
  return (
    plainRecord(value) &&
    Object.keys(value).length === 3 &&
    id(value.asset_id) &&
    id(value.version_id) &&
    typeof value.sha256 === 'string' &&
    /^[0-9a-f]{64}$/.test(value.sha256) &&
    !/[^0-9a-f]/.test(value.sha256)
  );
};

export const setIvrAudioReference = (graph, index, value) => {
  const node = graph.nodes[index];
  if (
    node?.type !== 'menu' ||
    (value !== null && !validIvrAudioReference(value))
  )
    throw new Error('invalid_ivr_graph');
  if (value === null) delete node.audio_reference;
  else {
    graph.schema_version = 2;
    node.audio_reference = { ...value };
  }
};

// Only a safe editing shape is checked here. Native schema, references and access remain authoritative.
export const parseIvrDraft = text => {
  if (
    typeof text !== 'string' ||
    new TextEncoder().encode(text).length > IVR_BYTES_LIMIT
  )
    throw new Error('invalid_ivr_graph');
  const graph = JSON.parse(text);
  const validNode = node =>
    plainRecord(node) &&
    typeof node.id === 'string' &&
    /^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(node.id) &&
    !/[^A-Za-z0-9_-]/.test(node.id) &&
    ['menu', 'queue', 'end'].includes(node.type) &&
    (!Object.hasOwn(node, 'audio_reference') ||
      (graph.schema_version === 2 &&
        node.type === 'menu' &&
        validIvrAudioReference(node.audio_reference))) &&
    (node.type !== 'menu' ||
      (Array.isArray(node.options) &&
        node.options.length <= 12 &&
        node.options.every(
          option =>
            plainRecord(option) &&
            typeof option.digit === 'string' &&
            typeof option.target === 'string'
        )));
  if (
    !plainRecord(graph) ||
    ![1, 2].includes(graph.schema_version) ||
    typeof graph.start !== 'string' ||
    !Array.isArray(graph.nodes) ||
    graph.nodes.length > IVR_NODES_LIMIT ||
    !graph.nodes.every(validNode) ||
    new Set(graph.nodes.map(node => node.id)).size !== graph.nodes.length
  )
    throw new Error('invalid_ivr_graph');
  return graph;
};

export const addIvrNode = (graph, type) => {
  if (
    !['menu', 'queue', 'end'].includes(type) ||
    graph.nodes.length >= IVR_NODES_LIMIT
  )
    throw new Error('invalid_ivr_graph');
  const identifiers = new Set(graph.nodes.map(node => node.id));
  let number = 1;
  while (identifiers.has(`node_${number}`)) number += 1;
  const node = { id: `node_${number}`, type };
  if (type === 'queue') node.queue_id = '';
  if (type === 'menu')
    Object.assign(node, {
      timeout_seconds: '',
      max_attempts: '',
      options: [],
      on_timeout: '',
      on_invalid: '',
    });
  graph.nodes.push(node);
};

export const removeIvrNode = (graph, id) => {
  graph.nodes = graph.nodes.filter(node => node.id !== id);
  if (graph.start === id) graph.start = '';
  graph.nodes
    .filter(node => node.type === 'menu')
    .forEach(node => {
      node.options.forEach(option => {
        if (option.target === id) option.target = '';
      });
      if (node.on_timeout === id) node.on_timeout = '';
      if (node.on_invalid === id) node.on_invalid = '';
    });
};

export const clearIvrAudioReferences = graph => {
  graph.nodes.forEach(node => {
    delete node.audio_reference;
  });
};

export const clearIvrQueues = graph => {
  graph.nodes
    .filter(node => node.type === 'queue')
    .forEach(node => {
      node.queue_id = '';
    });
};
