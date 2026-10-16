# frozen_string_literal: true

class JrcCustomers::RelationshipMap
  SAMPLE_LIMIT = 10
  NODE_FIELDS = %w[id display_id status created_at].freeze

  def initialize(root_key:, sources:)
    @root_key = root_key
    @sources = sources
  end

  def call
    groups = @sources.map { |kind, scope| group(kind, scope) }
    edges = groups.flat_map do |entry|
      entry[:nodes].map { |node| { source: @root_key, target: node[:key], relation: 'customer_context' } }
    end
    { version: 1, root: { key: @root_key }, groups: groups, edges: edges,
      sample_limit: SAMPLE_LIMIT, generated_at: Time.current.iso8601 }
  end

  private

  def group(kind, scope)
    total = scope.except(:order).distinct.count(:id)
    nodes = scope.distinct.reorder(created_at: :desc, id: :desc).limit(SAMPLE_LIMIT).map do |record|
      values = record.attributes
      values.slice(*NODE_FIELDS).symbolize_keys.merge(key: "#{kind}:#{record.id}", title: values['title'].presence || values['name'].presence)
    end
    { kind: kind, total: total, has_more: total > nodes.size, nodes: nodes }
  end
end
