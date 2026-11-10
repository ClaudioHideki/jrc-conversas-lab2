# frozen_string_literal: true

# Executes the real policy without Rails/DB. ActiveRecord locking and callbacks
# are covered separately by the Rails request/service specs, never by this fake.
require 'minitest/autorun'

module JrcContactCenter
  class OperationError < StandardError; end
end
require_relative '../../app/services/jrc_contact_center/acw_policy'

class VoiceAcwPolicyTest < Minitest::Test
  class Account
    attr_reader :settings

    def initialize(settings = {})
      @settings = settings
      @mutex = Mutex.new
    end

    def feature_enabled?(_feature)
      true
    end

    def with_lock(&block)
      @mutex.synchronize(&block)
    end

    def update!(settings:)
      @settings = settings
    end
  end

  def test_existing_companies_keep_required_voice_tabulation
    assert_equal true, JrcContactCenter::AcwPolicy.new(account: Account.new).call[:voice_required]
  end

  def test_optional_voice_is_explicit_and_keeps_reason_and_result_on_started_records
    account = Account.new('jrc_contact_center_acw' => { 'voice_required' => false })
    policy = JrcContactCenter::AcwPolicy.new(account: account).call
    assert_equal false, policy[:voice_required]
    assert_equal true, policy[:require_reason]
    assert_equal true, policy[:require_result]
  end

  def test_legacy_duration_update_preserves_mode_and_unrelated_settings
    account = Account.new('other' => 'preserve', 'jrc_contact_center_acw' => { 'voice_required' => false })
    policy = JrcContactCenter::AcwPolicy.new(account: account)
    result = policy.update!({ voice: 30, whatsapp: 45 })
    assert_equal false, result[:voice_required]
    assert_equal({ 'voice' => 30, 'whatsapp' => 45 }, result[:limits])
    assert_equal 'preserve', account.settings['other']
    assert_equal false, policy.update!(voice: 40, whatsapp: 50)[:voice_required]
  end

  def test_boolean_policy_is_scoped_to_one_company
    first = JrcContactCenter::AcwPolicy.new(account: Account.new)
    second = JrcContactCenter::AcwPolicy.new(account: Account.new)
    assert_equal false, first.update!({ voice: 30, whatsapp: 45 }, voice_required: false)[:voice_required]
    assert_equal true, second.call[:voice_required]
  end

  def test_rejects_non_boolean_modes_without_writing_settings
    account = Account.new
    policy = JrcContactCenter::AcwPolicy.new(account: account)
    ['false', nil, 0, {}].each do |mode|
      assert_raises(JrcContactCenter::OperationError) { policy.update!({ voice: 30, whatsapp: 45 }, voice_required: mode) }
    end
    assert_empty account.settings
  end
end
