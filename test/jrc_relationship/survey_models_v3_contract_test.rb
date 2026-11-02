# frozen_string_literal: true
# Pure Ruby contract/schema/scale validation, deliberately no Rails or database.
require 'minitest/autorun'
require 'json'
module JrcRelationship; end
require_relative '../../app/services/jrc_relationship/survey_question_schema'
require_relative '../../app/services/jrc_relationship/survey_model_contract'
require_relative '../../app/services/jrc_relationship/survey_scale'

class SurveyModelsV3ContractTest < Minitest::Test
  def payload
    { 'code' => 'synthetic_model', 'name' => 'Survey', 'description' => '', 'kind' => 'nps', 'active' => true,
      'unit_id' => 1, 'operator_id' => 1,
      'questions' => [{ 'key' => 'score', 'text' => 'Question?', 'type' => 'scale', 'required' => true, 'min' => 0, 'max' => 10 }],
      'settings' => { 'thank_you' => 'Thanks', 'ces_direction' => 'higher_is_better' },
      'channels' => { 'whatsapp' => { 'enabled' => false }, 'email' => { 'enabled' => false }, 'public_link' => { 'enabled' => true } },
      'rules' => { 'event' => 'closed', 'delay_minutes' => 0, 'frequency_days' => 30, 'expires_hours' => 168,
                   'priority' => 100, 'consent_required' => true, 'execution_member_id' => 1,
                   'channel_order' => %w[whatsapp email public_link], 'send_window' => { 'enabled' => false } },
      'permissions' => { 'team_ids' => [], 'edit_roles' => ['administrator'], 'publish_roles' => ['administrator'],
                         'response_roles' => ['administrator'], 'report_roles' => ['administrator'],
                         'share_relationship' => false, 'share_reports' => true, 'customer_own_response' => true } }
  end
  def test_valid_native_portal_contract
    c = JrcRelationship::SurveyModelContract.new(payload)
    assert c.valid?, c.errors.inspect
  end
  def test_custom_csat_and_ces_scales_preserve_nps_fixed
    %w[csat ces].each do |kind|
      p = payload; p['kind'] = kind; p['questions'][0].merge!('min' => 1, 'max' => 7)
      assert JrcRelationship::SurveyModelContract.new(p).valid?
      s = JrcRelationship::SurveyQuestionSchema.new(p['questions'])
      assert s.principal_scale?(kind, configurable: true)
      refute s.principal_scale?(kind)
    end
  end
  INVALIDS = {
    unknown_top: ->(p) { p['other_account'] = 8 }, blank_name: ->(p) { p['name'] = ' ' }, long_name: ->(p) { p['name'] = 'x' * 121 },
    no_unit: ->(p) { p['unit_id'] = nil }, no_operator: ->(p) { p['operator_id'] = -1 }, bad_kind: ->(p) { p['kind'] = 'fake' },
    bad_code: ->(p) { p['code'] = 'UNSAFE/ID' }, bad_active: ->(p) { p['active'] = 'true' },
    no_questions: ->(p) { p['questions'] = [] }, bad_question: ->(p) { p['questions'] = [nil] },
    duplicate_question: ->(p) { p['questions'] *= 2 }, nps_bounds: ->(p) { p['questions'][0]['max'] = 5 },
    optional_primary: ->(p) { p['questions'][0]['required'] = false }, primary_text: ->(p) { p['questions'][0]['type'] = 'text' },
    forward_condition: ->(p) { p['questions'][0]['condition'] = { 'question' => 'later', 'operator' => 'eq', 'value' => 1 } },
    unknown_channel: ->(p) { p['channels']['sms'] = { 'enabled' => true } }, missing_channel_schema: ->(p) { p['channels'].delete('email') },
    no_enabled_channel: ->(p) { p['channels']['public_link']['enabled'] = false },
    bad_channel: ->(p) { p['channels']['email'] = true }, email_without_inbox: ->(p) { p['channels']['email'] = { 'enabled' => true, 'message' => '{{survey_link}}' } },
    email_without_link: ->(p) { p['channels']['email'] = { 'enabled' => true, 'inbox_id' => 1, 'message' => 'No link' } },
    bad_event: ->(p) { p['rules']['event'] = 'untrusted' }, no_executor: ->(p) { p['rules']['execution_member_id'] = nil },
    no_consent: ->(p) { p['rules']['consent_required'] = false }, negative_delay: ->(p) { p['rules']['delay_minutes'] = -1 },
    fractional_expiry: ->(p) { p['rules']['expires_hours'] = 1.5 }, bad_order: ->(p) { p['rules']['channel_order'] = [0, {}] },
    repeated_order: ->(p) { p['rules']['channel_order'] = %w[email email public_link] },
    invalid_team: ->(p) { p['permissions']['team_ids'] = ['bad'] }, no_admin: ->(p) { p['permissions']['publish_roles'] = ['agent'] },
    unknown_role: ->(p) { p['permissions']['edit_roles'] << 'root' }, sharing_not_boolean: ->(p) { p['permissions']['share_relationship'] = 1 },
    unknown_settings: ->(p) { p['settings']['sensitive'] = 1 }, threshold_outside: ->(p) { p['settings']['low_threshold'] = 99 },
    invalid_presentation: ->(p) { p['questions'][0]['presentation'] = 'executable' }
  }.freeze
  INVALIDS.each do |name, mutate|
    define_method("test_rejects_#{name}") do
      p = payload; mutate.call(p); c = JrcRelationship::SurveyModelContract.new(p)
      refute c.valid?, name.to_s
      assert(c.errors.all? { |e| e[:step].is_a?(Integer) && e[:message].is_a?(String) })
      assert_raises(JrcRelationship::SurveyModelContract::Invalid) { c.validate! }
    end
  end
  def test_window_syntax_and_bounds
    p = payload; p['rules']['send_window'] = { 'enabled' => true, 'timezone' => 'America/Sao_Paulo', 'days' => [1,2,3], 'start' => '08:00', 'end' => '18:00' }
    assert JrcRelationship::SurveyModelContract.new(p).valid?
    p['rules']['send_window']['start'] = '25:00'
    refute JrcRelationship::SurveyModelContract.new(p).valid?
    p['rules']['send_window']['start'] = '20:00'
    refute JrcRelationship::SurveyModelContract.new(p).valid?
  end
  def test_scale_normalizes_without_mutating_original
    q = { 'min' => 1, 'max' => 7 }
    assert_equal 1.0, JrcRelationship::SurveyScale.normalize(1,q,low:1,high:5)
    assert_equal 3.0, JrcRelationship::SurveyScale.normalize(4,q,low:1,high:5)
    assert_equal 5.0, JrcRelationship::SurveyScale.normalize(7,q,low:1,high:5)
    assert_nil JrcRelationship::SurveyScale.normalize(8,q,low:1,high:5)
    assert_equal({ 'min' => 1, 'max' => 7 },q)
  end
  def test_zero_width_scale_is_rejected
    assert_nil JrcRelationship::SurveyScale.normalize(1,{ 'min'=>1,'max'=>1 },low:0,high:10)
  end
  def test_legacy_and_direction_sql_are_explicit
    sql = JrcRelationship::SurveyScale.sql('ces',reverse:true)
    assert_includes sql, 'ELSE score'
    assert_includes sql, 'lower_is_better'
    assert_raises(ArgumentError) { JrcRelationship::SurveyScale.sql('unsafe') }
  end
end
