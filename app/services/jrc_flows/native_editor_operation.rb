require 'uri'
module JrcFlows; end

class JrcFlows::NativeEditorOperation
  class Invalid < StandardError; end
  Operation = Struct.new(:method, :path, :scope, :request_limit, :response_limit, keyword_init: true)
  GRAPH_LIMIT = 2_200_000
  CONTROL_LIMIT = 16_384
  PREFIX = '/v1/delegated-flows'.freeze
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
  # Operation, verb, suffix, authority, graph request, graph response, identifier.
  TABLE = {
    'list' => [:get, '', 'flow:read', false, true, false],
    'create' => [:post, '', 'flow:edit', true, true, false],
    'import_preview' => [:post, '/import-preview', 'flow:edit', true, true, false],
    'status' => [:get, '/status', 'flow:read', false, false, false],
    'nodes' => [:get, '/nodes', 'flow:read', false, false, false],
    'get' => [:get, '', 'flow:read', false, true, true],
    'save' => [:put, '', 'flow:edit', true, true, true],
    'scope' => [:get, '/scope', 'flow:read', false, false, true],
    'validate' => [:post, '/validate', 'flow:edit', false, false, true],
    'simulate' => [:post, '/simulate', 'flow:edit', true, true, true],
    'publish' => [:post, '/publish', 'flow:publish', false, true, true],
    'versions' => [:get, '/versions-page', 'flow:read', false, true, true],
    'targets' => [:get, '/targets', 'flow:read', false, false, false],
    'bind' => [:post, '/bindings', 'flow:bind', false, false, true],
    'http_catalog' => [:get, '/http-credentials', 'flow:read', false, false, true],
    'subflow_catalog' => [:get, '/subflow-catalog', 'flow:read', false, false, true],
    'ai_catalog' => [:get, '/ai-credentials', 'flow:read', false, false, true],
    'handoff_connections' => [:get, '/handoff-connections', 'flow:read', false, false, true],
    'local_handoff_channels' => [:get, '/local-handoff-channels', 'flow:read', false, false, true],
    'handoff_catalog' => [:get, '', 'flow:read', false, false, true],
    'local_handoff_catalog' => [:get, '', 'flow:read', false, false, true],
    'resource_channels' => [:get, '/resource-channels', 'flow:read', false, false, true],
    'action_catalog' => [:get, '', 'flow:read', false, true, true],
    'save_action_resource' => [:post, '', 'flow:edit', false, false, true],
    'media_catalog' => [:get, '', 'flow:read', false, true, true],
    'revoke_media' => [:post, '', 'flow:edit', false, false, true],
    'cutover_get' => [:get, '', 'flow:bind', false, false, true],
    'cutover_prepare' => [:post, '/prepare', 'flow:bind', false, false, true],
    'cutover_reconcile' => [:post, '/reconcile', 'flow:bind', false, false, true]
  }.freeze
  PAGINATED = %w[list versions http_catalog subflow_catalog ai_catalog resource_channels action_catalog].freeze
  TARGET_PATHS = {
    'handoff_catalog' => '/integrations/%s/attendance-catalog', 'local_handoff_catalog' => '/channels/%s/local-attendance-catalog',
    'action_catalog' => '/channels/%s/action-catalog', 'save_action_resource' => '/channels/%s/action-resources',
    'media_catalog' => '/channels/%s/media', 'revoke_media' => '/channels/%s/media'
  }.freeze

  def self.resolve!(operation, id: nil, cursor: nil, target_id: nil, resource_id: nil)
    spec = TABLE[operation]
    raise Invalid unless spec

    verb, suffix, scope, graph_request, graph_response, needs_id = spec
    raise Invalid if needs_id ? !uuid?(id) : !id.nil?

    path = operation_path(operation, id, suffix) + target_path(operation, target_id, resource_id) + pagination(operation, cursor)
    Operation.new(method: verb, path: path, scope: scope,
                  request_limit: graph_request ? GRAPH_LIMIT : CONTROL_LIMIT,
                  response_limit: graph_response ? GRAPH_LIMIT : CONTROL_LIMIT)
  end

  def self.uuid?(value)
    value.is_a?(String) && UUID.match?(value)
  end

  def self.operation_path(operation, id, suffix)
    return PREFIX + "/integrations/#{id}/cutover" + suffix if operation.start_with?('cutover_')

    PREFIX + (id ? "/#{id}" : '') + suffix
  end

  def self.target_path(operation, target_id, resource_id)
    template = TARGET_PATHS[operation]
    raise Invalid if template ? !uuid?(target_id) : !target_id.nil?
    raise Invalid if operation == 'revoke_media' ? !uuid?(resource_id) : !resource_id.nil?

    path = template ? format(template, target_id) : ''
    operation == 'revoke_media' ? path + "/#{resource_id}/revoke" : path
  end

  def self.pagination(operation, cursor)
    raise Invalid if cursor && (!PAGINATED.include?(operation) || !cursor.is_a?(String) || !/\A[A-Za-z0-9_-]{1,256}\z/.match?(cursor))
    return '' unless PAGINATED.include?(operation)

    '?pageSize=1' + (cursor ? "&cursor=#{cursor}" : '')
  end

  def self.graph_request?(method, path)
    uuid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}'
    prefix = "\\A/api/v1/accounts/[1-9][0-9]*/jrc_flow_delegation/sessions/#{uuid}/flows"
    (method == 'POST' && %r{#{prefix}(?:/#{uuid}/simulate|/import-preview)?\z}.match?(path)) ||
      (method == 'PUT' && %r{#{prefix}/#{uuid}\z}.match?(path))
  end
end
