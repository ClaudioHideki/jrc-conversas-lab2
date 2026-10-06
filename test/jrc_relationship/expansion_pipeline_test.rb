require 'minitest/autorun'
module JrcRelationship; end
require_relative '../../app/services/jrc_relationship/expansion_pipeline'
class RelationshipExpansionPipelineTest < Minitest::Test
  class Rows
    attr_reader :rows
    def initialize(rows); @rows=rows; end
    def where(**filters)
      self.class.new(@rows.select { |row| filters.all? { |key,value| Array(value).include?(row[key]) || value.nil? && row[key].nil? } })
    end
    def select(key); @rows.map { |row| row[key] }; end
    def or(other); self.class.new((@rows + other.rows).uniq); end
  end
  def test_open_pipeline_excludes_won_lost_archived_rejected_and_hidden_deals
    deals = Rows.new([{ id:1,status:'open' }, { id:2,status:'won' }, { id:3,status:'lost' }, { id:4,status:'archived' }])
    signals = Rows.new([{ id:1,status:'suggested',deal_id:nil },{ id:2,status:'converted',deal_id:1 },
      { id:3,status:'converted',deal_id:2 },{ id:4,status:'converted',deal_id:3 },{ id:5,status:'converted',deal_id:4 },
      { id:6,status:'rejected',deal_id:nil },{ id:7,status:'converted',deal_id:999 }])
    assert_equal [1,2], JrcRelationship::ExpansionPipeline.open(signals,deals).select(:id)
    assert_equal [1], JrcRelationship::ExpansionPipeline.open(signals,Rows.new([])).select(:id)
  end
end
