# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../../app/services/jrc_flows/native_editor_operation'

class NativeBoxRoutingContractTest < Minitest::Test
  ROOT = '11111111-1111-4111-8111-111111111111'
  CHANNEL = '22222222-2222-4222-8222-222222222222'
  API = JrcFlows::NativeEditorOperation

  def test_catalog_is_scoped_to_root_channel_and_explicit_version
    op = API.resolve!('box_routing', id: ROOT, target_id: CHANNEL, query: { 'version' => '2', 'teamId' => '7' })
    assert_equal "/v1/delegated-flows/#{ROOT}/channels/#{CHANNEL}/box-routing?teamId=7&version=2", op.path
    assert_equal :get, op.http_method
    assert_equal 'flow:read', op.scope
    assert_equal API::GRAPH_LIMIT, op.response_limit
    write = API.resolve!('save_box_routing', id: ROOT, target_id: CHANNEL)
    assert_equal :put, write.http_method
    assert_equal 'flow:edit', write.scope
    assert_equal API::CONTROL_LIMIT, write.request_limit
  end

  def test_catalog_rejects_authority_injection_missing_version_and_invalid_targets
    [{}, { 'version' => '0' }, { 'version' => '2', 'accountId' => '1' }, { 'version' => ['1', '2'] }].each do |query|
      assert_raises(API::Invalid) { API.resolve!('box_routing', id: ROOT, target_id: CHANNEL, query: query) }
    end
    assert_raises(API::Invalid) { API.resolve!('box_routing', id: ROOT, target_id: '../escape', query: { 'version' => '1' }) }
    assert_raises(API::Invalid) { API.resolve!('save_box_routing', id: ROOT, target_id: CHANNEL, query: { 'version' => '1' }) }
  end
end
