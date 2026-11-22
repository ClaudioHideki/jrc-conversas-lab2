# frozen_string_literal: true

# Proves that every configured node has a path to a logical terminal.
class JrcContactCenter::IvrGraphPaths
  def self.targets(node)
    return node.values_at('on_open', 'on_closed') if node.fetch('type') == 'calendar'
    return [] unless node.fetch('type') == 'menu'

    node.fetch('options').pluck('target') + node.values_at('on_timeout', 'on_invalid')
  end

  def self.validate!(nodes)
    reverse = reverse_edges(nodes)
    terminal = nodes.values.select { |node| %w[end queue].include?(node.fetch('type')) }.pluck('id')
    reached = terminal.to_set
    terminal.each { |id| reverse[id].each { |parent| terminal << parent if reached.add?(parent) } }
    raise JrcContactCenter::OperationError, 'ivr_closed_loop' unless reached.length == nodes.length
  end

  def self.reverse_edges(nodes)
    reverse = Hash.new { |hash, key| hash[key] = [] }
    nodes.each_value do |node|
      targets(node).each do |target|
        raise JrcContactCenter::OperationError, 'ivr_missing_target' unless nodes.key?(target)

        reverse[target] << node.fetch('id')
      end
    end
    reverse
  end
  private_class_method :reverse_edges
end
