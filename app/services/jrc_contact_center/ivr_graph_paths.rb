# frozen_string_literal: true

# Proves that every configured node has a path to a logical terminal.
class JrcContactCenter::IvrGraphPaths
  def self.targets(node)
    return [] unless node.fetch('type') == 'menu'

    node.fetch('options').pluck('target') + node.values_at('on_timeout', 'on_invalid')
  end

  def self.validate!(nodes)
    reverse = Hash.new { |hash, key| hash[key] = [] }
    terminal = []
    nodes.each_value do |node|
      terminal << node.fetch('id') unless node.fetch('type') == 'menu'
      targets(node).each do |target|
        raise JrcContactCenter::OperationError, 'ivr_missing_target' unless nodes.key?(target)

        reverse[target] << node.fetch('id')
      end
    end
    reached = terminal.to_set
    terminal.each { |id| reverse[id].each { |parent| terminal << parent if reached.add?(parent) } }
    raise JrcContactCenter::OperationError, 'ivr_closed_loop' unless reached.length == nodes.length
  end
end
