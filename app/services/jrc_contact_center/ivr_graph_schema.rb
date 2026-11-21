# frozen_string_literal: true

# Local JRC draft schema. This is not a PABX configuration/codec contract.
class JrcContactCenter::IvrGraphSchema
  NODE_ID = { 'type' => 'string', 'minLength' => 1, 'maxLength' => 64, 'pattern' => '^[A-Za-z]',
              'not' => { 'pattern' => '[^A-Za-z0-9_-]' } }.freeze
  QUEUE_ID = { 'type' => 'string', 'minLength' => 1, 'maxLength' => 19, 'pattern' => '^[1-9]',
               'not' => { 'pattern' => '[^0-9]' } }.freeze
  TERMINAL = {
    'type' => 'object', 'required' => %w[id type], 'additionalProperties' => false,
    'properties' => { 'id' => NODE_ID, 'type' => { 'const' => 'end' } }
  }.freeze
  QUEUE = {
    'type' => 'object', 'required' => %w[id type queue_id], 'additionalProperties' => false,
    'properties' => { 'id' => NODE_ID, 'type' => { 'const' => 'queue' }, 'queue_id' => QUEUE_ID }
  }.freeze
  MENU = {
    'type' => 'object', 'required' => %w[id type options timeout_seconds max_attempts on_timeout on_invalid],
    'additionalProperties' => false, 'properties' => {
      'id' => NODE_ID, 'type' => { 'const' => 'menu' },
      'timeout_seconds' => { 'type' => 'integer', 'minimum' => 1, 'maximum' => 2_147_483_647 },
      'max_attempts' => { 'type' => 'integer', 'minimum' => 1, 'maximum' => 128 },
      'on_timeout' => NODE_ID, 'on_invalid' => NODE_ID,
      'options' => {
        'type' => 'array', 'minItems' => 1, 'maxItems' => 12, 'items' => {
          'type' => 'object', 'required' => %w[digit target], 'additionalProperties' => false,
          'properties' => { 'digit' => { 'type' => 'string', 'minLength' => 1, 'maxLength' => 1, 'pattern' => '^[0-9*#]$' }, 'target' => NODE_ID }
        }
      }
    }
  }.freeze
  SCHEMA = {
    '$schema' => 'http://json-schema.org/draft-07/schema#',
    'type' => 'object', 'required' => %w[schema_version start nodes], 'additionalProperties' => false,
    'properties' => {
      'schema_version' => { 'const' => 1 }, 'start' => NODE_ID,
      'nodes' => { 'type' => 'array', 'minItems' => 1, 'maxItems' => 128, 'items' => { 'oneOf' => [TERMINAL, QUEUE, MENU] } }
    }
  }.freeze

  AUDIO_REFERENCE = {
    'type' => 'object', 'required' => %w[asset_id version_id sha256], 'additionalProperties' => false,
    'properties' => {
      'asset_id' => QUEUE_ID, 'version_id' => QUEUE_ID,
      'sha256' => { 'type' => 'string', 'minLength' => 64, 'maxLength' => 64, 'pattern' => '^[0-9a-f]{64}$' }
    }
  }.freeze
  MENU_V2 = MENU.deep_dup.tap { |schema| schema.fetch('properties')['audio_reference'] = AUDIO_REFERENCE }.freeze
  SCHEMA_V2 = SCHEMA.deep_dup.tap do |schema|
    schema.fetch('properties')['schema_version'] = { 'const' => 2 }
    schema.dig('properties', 'nodes', 'items')['oneOf'] = [TERMINAL, QUEUE, MENU_V2]
  end.freeze

  def self.validate!(graph)
    versioned = graph.is_a?(Hash) && graph['schema_version'].is_a?(Integer)
    schema = versioned && { 1 => SCHEMA, 2 => SCHEMA_V2 }[graph['schema_version']]
    return if schema && JSONSchemer.schema(schema).valid?(graph) && JSON.generate(graph).bytesize <= 1.megabyte

    raise JrcContactCenter::OperationError, 'invalid_ivr_graph'
  end
end
