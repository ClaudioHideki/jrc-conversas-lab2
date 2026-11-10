require 'minitest/autorun'
require 'json'
module JrcBackoffice; end
require_relative '../app/services/jrc_backoffice/requirement_definition'
require_relative '../app/services/jrc_backoffice/requirement_evaluation'

class RequirementDefinitionTest < Minitest::Test
  Definition = JrcBackoffice::RequirementDefinition
  def base(kind = 'information')
    { 'label' => 'Signer contact', 'kind' => kind, 'required' => true, 'blocking' => true, 'stage' => 'documentation' }
  end
  def row(kind = 'information')
    value = base(kind)
    value['answer_type'] = 'text' if kind == 'information'
    value
  end
  def test_normalizes_label_without_mutating_source
    value = row.merge('label' => '  Contact  ')
    assert_equal 'Contact', Definition.normalize(value)['label']
    assert_equal '  Contact  ', value['label']
  end
  def test_all_six_leaf_kinds
    inputs = [row, row('document').merge('document_key' => 'social_contract'),
              row('validation').merge('source' => 'manual_review'), row('approval').merge('source' => 'backoffice.release', 'stage' => 'approval'),
              row('signature').merge('stage' => 'contract'), row('field').merge('field' => 'contact.email')]
    inputs.each { |input| assert_equal input['kind'], Definition.normalize(input)['kind'] }
  end
  def conditional
    base('conditional').merge('requirement_kind' => 'document', 'document_key' => 'power_of_attorney',
      'conditions' => [{ 'field' => 'customer_kind', 'operator' => 'equal', 'value' => 'company' }])
  end
  def test_seventh_kind_conditional
    assert_equal 'document', Definition.leaf_kind(Definition.normalize(conditional))
  end
  def test_unknown_type_is_rejected
    assert_raises(ArgumentError) { Definition.normalize(row.merge('kind' => 'execute_sql')) }
  end
  def test_unknown_field_is_rejected
    assert_raises(ArgumentError) { Definition.normalize(row.merge('approved' => true)) }
  end
  def test_no_implicit_boolean_cast
    assert_raises(ArgumentError) { Definition.normalize(row.merge('blocking' => 'false')) }
  end
  def test_non_required_item_cannot_block
    assert_raises(ArgumentError) { Definition.normalize(row.merge('required' => false)) }
  end
  def test_explicit_nonblocking_optional_item
    assert_equal false, Definition.normalize(row.merge('required' => false, 'blocking' => false))['blocking']
  end
  def test_unknown_stage_rejected
    assert_raises(ArgumentError) { Definition.normalize(row.merge('stage' => 'done')) }
  end
  def test_blank_and_large_labels_rejected
    ['', '  ', 'x' * 201].each { |label| assert_raises(ArgumentError) { Definition.normalize(row.merge('label' => label)) } }
  end
  def test_invalid_document_keys
    [nil, false, '../private', 'A', 'x' * 81].each do |key|
      assert_raises(ArgumentError) { Definition.normalize(row('document').merge('document_key' => key)) }
    end
  end
  def test_private_signature_artifact_cannot_be_configured_as_manual_document
    %w[contract_signed contract_generated signature_delivery_42_certificate].each do |key|
      assert_raises(ArgumentError) { Definition.normalize(row('document').merge('document_key' => key)) }
    end
  end
  def test_unknown_information_type
    assert_raises(ArgumentError) { Definition.normalize(row.merge('answer_type' => 'json')) }
  end
  def test_no_arbitrary_registration_path
    assert_raises(ArgumentError) { Definition.normalize(row('field').merge('field' => 'user.encrypted_password')) }
  end
  def test_no_arbitrary_approval_source
    assert_raises(ArgumentError) { Definition.normalize(row('approval').merge('source' => 'other.approval')) }
  end
  def test_no_automatic_legal_validation
    assert_raises(ArgumentError) { Definition.normalize(row('validation').merge('source' => 'auto_legal_authority')) }
  end
  def test_signature_cannot_block_before_contract_exists
    assert_raises(ArgumentError) { Definition.normalize(row('signature')) }
  end
  def test_wrong_type_extra_fields_rejected
    assert_raises(ArgumentError) { Definition.normalize(row.merge('document_key' => 'rg')) }
  end
  def test_conditional_needs_conditions
    assert_raises(ArgumentError) { Definition.normalize(conditional.merge('conditions' => [])) }
  end
  def test_no_recursive_conditional
    assert_raises(ArgumentError) { Definition.normalize(conditional.merge('requirement_kind' => 'conditional')) }
  end
  def test_nonconditional_cannot_smuggle_conditions
    assert_raises(ArgumentError) { Definition.normalize(row.merge('conditions' => [])) }
  end
  def test_condition_unknown_field
    value = conditional.merge('conditions' => [{ 'field' => 'actor.role', 'operator' => 'equal', 'value' => 'admin' }])
    assert_raises(ArgumentError) { Definition.normalize(value) }
  end
  def test_condition_references_are_typed
    value = conditional.merge('conditions' => [{ 'field' => 'product_id', 'operator' => 'equal', 'value' => '2' }])
    assert_raises(ArgumentError) { Definition.normalize(value) }
  end
  def test_condition_values_are_bounded
    value = conditional.merge('conditions' => [{ 'field' => 'product_id', 'operator' => 'in', 'value' => (1..21).to_a }])
    assert_raises(ArgumentError) { Definition.normalize(value) }
  end
  def test_missing_condition_is_unknown_not_optional
    assert_equal :unknown, Definition.applicable(conditional, {})
    assert_equal :unknown, Definition.applicable(conditional, { 'customer_kind' => nil })
  end
  def test_known_false_condition_is_not_applicable
    assert_equal false, Definition.applicable(conditional, { 'customer_kind' => 'individual' })
  end
  def test_matching_company_condition
    assert_equal true, Definition.applicable(conditional, { 'customer_kind' => 'company' })
  end
  def test_product_membership_condition
    value = conditional.merge('conditions' => [{ 'field' => 'product_id', 'operator' => 'in', 'value' => [2, 4] }])
    assert Definition.applicable(value, { 'product_id' => [1, 2] })
    refute Definition.applicable(value, { 'product_id' => [5, 6] })
  end
  def test_product_not_equal
    value = conditional.merge('conditions' => [{ 'field' => 'product_id', 'operator' => 'not_equal', 'value' => 2 }])
    refute Definition.applicable(value, { 'product_id' => [1, 2] })
    assert Definition.applicable(value, { 'product_id' => [1] })
  end
  def test_boolean_false_is_a_valid_information_answer
    assert_equal false, Definition.answer!(row.merge('answer_type' => 'boolean'), false)
  end
  def test_no_string_boolean_coercion
    assert_raises(ArgumentError) { Definition.answer!(row.merge('answer_type' => 'boolean'), 'false') }
  end
  def test_numeric_zero_is_present
    assert_equal 0, Definition.answer!(row.merge('answer_type' => 'number'), 0)
  end
  def test_nonfinite_numbers_rejected
    [Float::NAN, Float::INFINITY, '3'].each do |value|
      assert_raises(ArgumentError) { Definition.answer!(row.merge('answer_type' => 'number'), value) }
    end
  end
  def test_email_and_phone
    assert_equal 'signer@example.test', Definition.answer!(row.merge('answer_type' => 'email'), 'signer@example.test')
    assert_raises(ArgumentError) { Definition.answer!(row.merge('answer_type' => 'email'), 'invalid@') }
    assert_equal '+55 (11) 90000-0000', Definition.answer!(row.merge('answer_type' => 'phone'), '+55 (11) 90000-0000')
    assert_raises(ArgumentError) { Definition.answer!(row.merge('answer_type' => 'phone'), 'extension 1') }
  end
  def test_no_manual_signature_response
    assert_raises(ArgumentError) { Definition.answer!(row('signature'), true) }
  end
  def test_digest_is_key_order_independent_and_value_sensitive
    assert_equal Definition.digest({ 'a' => 1, 'b' => { 'd' => false, 'c' => 2 } }),
                 Definition.digest({ 'b' => { 'c' => 2, 'd' => false }, 'a' => 1 })
    refute_equal Definition.digest({ 'a' => 0 }), Definition.digest({ 'a' => nil })
  end
  def evaluate(definition, response: {}, facts: {}, source: ->(*) { 'satisfied' }, through: nil, scope: {})
    JrcBackoffice::RequirementEvaluation.new(rows: [{ 'key' => 'r1', 'definition' => definition, 'scope' => scope }],
      facts: facts, responses: response, source: source).call(through: through).first
  end
  def test_missing_information_blocks
    result = evaluate(row)
    assert_equal 'missing', result[:status]
    assert result[:blocking]
  end
  def test_false_answer_satisfies_boolean_information
    result = evaluate(row.merge('answer_type' => 'boolean'), response: { 'r1' => { 'value' => false, 'revision' => 2 } })
    assert_equal 'satisfied', result[:status]
    assert_equal 2, result[:response_revision]
    refute result[:blocking]
  end
  def test_pending_manual_review_cannot_fall_back_to_native_success
    result = evaluate(row('validation').merge('source' => 'manual_review'))
    assert_equal 'pending', result[:status]
    assert result[:blocking]
  end
  def test_explicit_review_approval_and_rejection
    definition = row('validation').merge('source' => 'manual_review')
    assert_equal 'satisfied', evaluate(definition, response: { 'r1' => { 'decision' => 'approved' } })[:status]
    assert_equal 'rejected', evaluate(definition, response: { 'r1' => { 'decision' => 'rejected' } })[:status]
  end
  def test_submitted_signature_payload_is_never_evidence
    result = evaluate(row('signature').merge('stage' => 'contract'), response: { 'r1' => { 'value' => true, 'decision' => 'approved' } },
      source: ->(*) { 'pending' })
    assert_equal 'pending', result[:status]
    assert result[:blocking]
  end
  def test_all_native_denials_remain_blocking
    %w[missing pending rejected expired quarantined unavailable].each do |state|
      result = evaluate(row('document').merge('document_key' => 'rg'), source: ->(*) { state })
      assert result[:blocking], state
    end
  end
  def test_source_error_is_not_success
    assert_raises(RuntimeError) do
      evaluate(row('field').merge('field' => 'customer.tax_id'), source: ->(*) { raise 'unavailable' })
    end
  end
  def test_unknown_native_state_is_rejected
    assert_raises(ArgumentError) do
      evaluate(row('approval').merge('source' => 'backoffice.release', 'stage' => 'approval'), source: ->(*) { true })
    end
  end
  def test_nonblocking_item_is_visible_without_blocking
    result = evaluate(row.merge('blocking' => false))
    assert_equal 'missing', result[:status]
    refute result[:blocking]
  end
  def test_later_signature_does_not_prevent_documentation_stage
    result = evaluate(row('signature').merge('stage' => 'contract'), through: 'documentation', source: ->(*) { 'pending' })
    refute result[:blocking]
    assert_equal 'pending', result[:status]
  end
  def test_prior_stage_remains_enforced
    assert evaluate(row, through: 'finance')[:blocking]
  end
  def test_unknown_scope_is_not_zero_or_not_applicable
    result = evaluate(row, scope: { 'customer_kind' => 'company' })
    assert_equal 'unavailable', result[:status]
    assert result[:blocking]
  end
  def test_conditional_false_does_not_call_document_source
    result = evaluate(conditional, facts: { 'customer_kind' => 'individual' }, source: ->(*) { flunk 'unexpected native read' })
    assert_equal 'not_applicable', result[:status]
    refute result[:blocking]
  end
  def test_approval_cannot_be_postponed_until_after_contract
    assert_raises(ArgumentError) do
      Definition.normalize(row('approval').merge('source' => 'backoffice.release', 'stage' => 'finance'))
    end
  end
  def test_contract_signature_policy_requires_existing_contract_stage
    rule = row('approval').merge('source' => 'contracts.company_signature', 'stage' => 'contract')
    assert_equal 'contract', Definition.normalize(rule)['stage']
    assert_raises(ArgumentError) { Definition.normalize(rule.merge('stage' => 'approval')) }
  end

end

class RequirementReleaseStageTest < Minitest::Test
  def test_signature_is_a_post_send_release_requirement
    assert JrcBackoffice::RequirementDefinition.post_signature?('kind' => 'signature')
  end
  def test_company_signature_approval_uses_native_post_signature_proof
    assert JrcBackoffice::RequirementDefinition.post_signature?('kind' => 'approval', 'source' => 'contracts.company_signature')
  end
  def test_commercial_approval_must_not_be_skipped_before_send
    refute JrcBackoffice::RequirementDefinition.post_signature?('kind' => 'approval', 'source' => 'crm.order_price')
  end
  def test_conditional_signature_keeps_the_same_release_boundary
    assert JrcBackoffice::RequirementDefinition.post_signature?('kind' => 'conditional', 'requirement_kind' => 'signature')
  end
  def test_document_remains_a_pre_send_requirement
    refute JrcBackoffice::RequirementDefinition.post_signature?('kind' => 'document')
  end
end
