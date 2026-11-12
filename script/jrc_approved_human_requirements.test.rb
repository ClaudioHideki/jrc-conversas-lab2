require 'minitest/autorun'
module JrcBackoffice; end
require_relative '../app/services/jrc_backoffice/requirement_definition'
require_relative '../app/services/jrc_backoffice/requirement_evaluation'
class HumanRequirementTest < Minitest::Test
  D=JrcBackoffice::RequirementDefinition
  def row(kind='consultation')
    {'label'=>'Review native source','kind'=>kind,'required'=>true,'blocking'=>true,'stage'=>'documentation',
     'instructions'=>'Consult the permitted source and record the human result','reviewer_ids'=>[8], 'reviewer_team_ids'=>[]}
  end
  %w[consultation confirmation human_activity].each do |kind|
    define_method("test_#{kind}_is_supported") { assert_equal kind,D.normalize(row(kind))['kind'] }
    define_method("test_#{kind}_needs_reviewers") { assert_raises(ArgumentError){D.normalize(row(kind).merge('reviewer_ids'=>[]))} }
    define_method("test_#{kind}_needs_instructions") { assert_raises(ArgumentError){D.normalize(row(kind).merge('instructions'=>' '))} }
    define_method("test_#{kind}_cannot_receive_native_proof") { assert_raises(ArgumentError){D.response_payload!(row(kind),{'decision'=>'completed','note'=>'reviewed','signature'=>true})} }
  end
  def test_current_native_team_can_be_configured_without_user_list
    assert_equal [2],D.normalize(row.merge('reviewer_ids'=>[],'reviewer_team_ids'=>[2]))['reviewer_team_ids']
  end
  def test_confirmation_is_not_signature
    assert_equal({'decision'=>'confirmed','note'=>'Human confirmation'},D.response_payload!(row('confirmation'),{'decision'=>'confirmed','note'=>'Human confirmation'}))
    sig={'kind'=>'signature','stage'=>'contract'};assert_raises(ArgumentError){D.response_payload!(sig,{'decision'=>'confirmed','note'=>'Human confirmation'})}
  end
  def test_completed_activity_needs_a_note
    assert_raises(ArgumentError){D.response_payload!(row('human_activity'),{'decision'=>'completed','note'=>''})}
  end
  def test_rejection_remains_blocking_data
    assert_equal 'rejected',D.response_payload!(row,{'decision'=>'rejected','note'=>'Native reference is inconsistent'})['decision']
  end
  def test_document_human_review_flag_is_explicit
    doc={'label'=>'Power of attorney','kind'=>'document','required'=>true,'blocking'=>true,'stage'=>'contract','document_key'=>'proxy','requires_human_review'=>true}
    assert D.normalize(doc)['requires_human_review']
    assert_raises(ArgumentError){D.normalize(doc.merge('requires_human_review'=>'true'))}
  end
  def test_document_cannot_silently_reassign_reviewer_in_another_field
    doc=row.merge('kind'=>'document','document_key'=>'proxy');assert_raises(ArgumentError){D.normalize(doc)}
  end
  def test_signatory_powers_uses_native_source_not_human_checkbox
    validation={'label'=>'Signer powers','kind'=>'validation','source'=>'signatory_powers','required'=>true,'blocking'=>true,'stage'=>'contract'}
    assert_equal 'signatory_powers',D.normalize(validation)['source']
    assert_raises(ArgumentError){D.response_payload!(validation,{'decision'=>'approved'})}
    assert_raises(ArgumentError){D.normalize(validation.merge('stage'=>'documentation'))}
  end
  def test_conditions_can_wrap_human_review
    val=row.merge('kind'=>'conditional','requirement_kind'=>'human_activity','conditions'=>[{'field'=>'customer_kind','operator'=>'equal','value'=>'company'}])
    assert_equal 'human_activity',D.leaf_kind(D.normalize(val))
  end
  def test_native_approval_cannot_be_faked_by_human_response
    assert_raises(ArgumentError){D.response_payload!({'kind'=>'approval','source'=>'backoffice.release'},{'decision'=>'approved'})}
  end
  def test_duplicates_and_cross_type_reviewer_ids_are_rejected
    [[8,8],['8'],[false],[{}],[0]].each{|ids|assert_raises(ArgumentError){D.normalize(row.merge('reviewer_ids'=>ids))}}
  end
end

class ApprovedDraftRequirementStageTest < Minitest::Test
  def definition(stage)
    {'label'=>'Synthetic draft review','kind'=>'approval','source'=>'contracts.draft_review','stage'=>stage,'required'=>true,'blocking'=>true}
  end
  def test_draft_review_belongs_after_draft_generation
    assert_equal 'contract', JrcBackoffice::RequirementDefinition.normalize(definition('contract'))['stage']
    assert_raises(ArgumentError){JrcBackoffice::RequirementDefinition.normalize(definition('approval'))}
  end
  def test_draft_review_is_not_post_signature_evidence
    refute JrcBackoffice::RequirementDefinition.post_signature?(definition('contract'))
  end
end
