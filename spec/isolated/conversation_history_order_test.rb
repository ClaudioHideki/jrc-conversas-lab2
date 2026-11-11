# Query boundary harness of the real SortHandler. It does not execute PostgreSQL.
require 'json'

module ActiveSupport
  module Concern
    def class_methods(&block)
      const_set(:ClassMethods, Module.new(&block))
    end
  end
end

require_relative '../../app/models/concerns/sort_handler'
query = Object.new.extend(SortHandler::ClassMethods)
query.define_singleton_method(:order) { |attributes| attributes }
%i[asc desc].each do |direction|
  actual = query.sort_on_last_activity_at(direction)
  raise "missing deterministic tie order: #{actual.inspect}" unless actual == { last_activity_at: direction, id: :asc }
end
puts({ harness: 'real_sort_handler_query', cases: 2, rails: false, postgres: false, passed: true }.to_json)
