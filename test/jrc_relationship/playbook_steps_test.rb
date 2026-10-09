require 'minitest/autorun'
module JrcRelationship; end
require_relative '../../app/services/jrc_relationship/playbook_steps'
class RelationshipPlaybookStepsTest < Minitest::Test
  def test_onboarding_has_native_welcome_meeting_and_30_60_90_plan_and_tasks
    steps = JrcRelationship::PlaybookSteps.onboarding
    assert JrcRelationship::PlaybookSteps.valid?(steps)
    assert_equal 1, steps.count { |s| s['kind'] == 'success_plan' }
    assert_equal 1, steps.count { |s| s['kind'] == 'meeting' }
    assert_equal [30,60,90], steps.select { |s| s['kind'] == 'activity' }.map { |s| s['after_days'] }
  end
  def test_rejects_unbounded_or_external_or_empty_automation
    [[], Array.new(51) { { 'kind'=>'action', 'title'=>'Task', 'after_days'=>0 } },
     [{ 'kind'=>'send_email', 'title'=>'External', 'after_days'=>0 }],
     [{ 'kind'=>'risk', 'title'=>' ', 'after_days'=>0 }],
     [{ 'kind'=>'risk', 'title'=>'Risk', 'after_days'=>'abc' }],
     [{ 'kind'=>'risk', 'title'=>'Risk', 'after_days'=>-1 }],
     [{ 'kind'=>'risk', 'title'=>'Risk', 'after_days'=>366 }]].each do |steps|
      refute JrcRelationship::PlaybookSteps.valid?(steps)
    end
  end
  def test_duplicate_and_unsafe_keys_are_rejected
    step = { 'kind'=>'action', 'title'=>'Task', 'after_days'=>0, 'step_key'=>'fixed' }
    refute JrcRelationship::PlaybookSteps.valid?([step,step])
    refute JrcRelationship::PlaybookSteps.valid?([step.merge('step_key'=>'../unsafe')])
    assert JrcRelationship::PlaybookSteps.valid?([step, step.merge('step_key'=>'next')])
  end
  def test_all_supported_native_steps_validate
    JrcRelationship::PlaybookSteps::KINDS.each do |kind|
      step = { 'kind'=>kind, 'title'=>'Native work', 'after_days'=>365 }
      if kind == 'flow'
        step.merge!(
          'after_days' => 0,
          'step_key' => 'native-flow',
          'flow_id' => 1,
          'conversation_id' => 2,
          'contact_id' => 3,
          'flow_lock_version' => 0,
          'flow_digest' => 'a' * 64
        )
      end
      assert JrcRelationship::PlaybookSteps.valid?([step])
    end
  end
end
