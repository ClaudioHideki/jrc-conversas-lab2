require 'minitest/autorun'
module JrcBackoffice; end
module JrcCustomers; end
require_relative '../../app/services/jrc_customers/tax_identifier'
require_relative '../../app/services/jrc_backoffice/document_checks'

class DocumentChecksTest < Minitest::Test
  Service = JrcBackoffice::DocumentChecks
  COMPANY = '11222333000181'
  PERSON = '11144477735'

  def test_cnpj_valid_matches_without_returning_it
    result = Service.call(text: "CNPJ: 11.222.333/0001-81. Synthetic document for a company.", expected_identifier: COMPANY)
    assert_equal 'valid', result[:cnpj_checksum]
    assert_equal 'matches', result[:customer_identifier]
    refute_includes result.inspect, COMPANY
    refute_includes result.inspect, '11.222.333'
  end

  def test_cpf_valid_matches_without_returning_it
    result = Service.call(text: 'CPF: 111.444.777-35. Synthetic individual document.', expected_identifier: PERSON)
    assert_equal 'valid', result[:cpf_checksum]
    assert_equal 'matches', result[:customer_identifier]
    refute_includes result.inspect, PERSON
  end

  def test_empty_text_means_no_evidence_not_approval
    result = Service.call(text: '', expected_identifier: COMPANY)
    assert_equal 'not_found', result[:customer_identifier]
    assert_equal false, result[:readable_text]
  end

  def test_no_configured_customer
    assert_equal 'customer_unconfigured', Service.call(text: 'CNPJ: 11222333000181', expected_identifier: nil)[:customer_identifier]
  end

  def test_invalid_customer_never_matches
    assert_equal 'customer_invalid', Service.call(text: 'CNPJ: 00000000000000', expected_identifier: '00000000000000')[:customer_identifier]
  end

  def test_invalid_check_digits_stay_invalid
    result = Service.call(text: 'CNPJ: 11222333000180 CPF: 11144477734', expected_identifier: COMPANY)
    assert_equal 'invalid', result[:cnpj_checksum]
    assert_equal 'invalid', result[:cpf_checksum]
    assert_equal 'mismatch', result[:customer_identifier]
  end

  def test_different_identity_cannot_be_used_for_the_customer
    result = Service.call(text: 'CPF: 52998224725', expected_identifier: PERSON)
    assert_equal 'mismatch', result[:customer_identifier]
  end

  def test_multiple_identifiers_require_human_review
    result = Service.call(text: 'CPF: 11144477735 CPF: 52998224725', expected_identifier: PERSON)
    assert_equal 'ambiguous', result[:customer_identifier]
  end

  def test_duplicates_do_not_create_false_ambiguity
    assert_equal 'matches', Service.call(text: 'CPF: 11144477735 CPF: 111.444.777-35', expected_identifier: PERSON)[:customer_identifier]
  end

  def test_identifier_requires_an_explicit_label
    assert_equal 'not_found', Service.call(text: '11144477735 11222333000181', expected_identifier: COMPANY)[:customer_identifier]
  end

  def test_partial_number_is_not_accepted
    assert_equal 'not_found', Service.call(text: 'CPF: 111444777350', expected_identifier: PERSON)[:customer_identifier]
  end

  def test_cpf_of_a_signer_does_not_satisfy_the_company_check
    assert_equal 'not_found', Service.call(text: 'CPF: 11144477735', expected_identifier: COMPANY)[:customer_identifier]
  end

  def test_digital_text_does_not_claim_signature_or_powers
    result = Service.call(text: 'CPF: 11144477735 REPRESENTANTE LEGAL ASSINADO', expected_identifier: PERSON)
    refute result.key?(:signature)
    refute result.key?(:powers)
    refute result.key?(:approved)
    refute result.key?(:ocr_confidence)
  end

  def test_extraction_shape_is_not_guessed
    assert_raises(ArgumentError) { Service.call(text: nil, expected_identifier: COMPANY) }
  end
end
