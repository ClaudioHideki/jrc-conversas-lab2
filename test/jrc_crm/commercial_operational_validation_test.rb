require 'minitest/autorun'
require 'stringio'
require_relative '../../app/services/jrc_crm/contract_template_selection'
require_relative '../../app/services/jrc_crm/signed_pdf_validation'

class CommercialOperationalValidationTest < Minitest::Test
  Template = Struct.new(:id, :selection_rules)
  FileUpload = Struct.new(:tempfile, :size, :content_type, :original_filename)
  def test_specific_template_takes_precedence_over_default
    default = Template.new(1, {})
    wrong_account = Template.new(2, { 'operating_company_id' => 7 })
    correct = Template.new(3, { 'operating_company_id' => 8, 'product_ids' => [40], 'customer_kind' => 'pj' })
    assert_equal correct, JrcCrm::ContractTemplateSelection.select([default, wrong_account, correct],
      { 'operating_company_id' => 8, 'product_ids' => [40, 41], 'customer_kind' => 'pj' })
    assert_equal default, JrcCrm::ContractTemplateSelection.select([default, correct], { 'customer_kind' => 'pf' })
  end
  def test_all_finite_criteria_and_unknown_rules_fail_closed
    rules = { 'order_origins' => ['renewal'], 'payment_conditions' => ['30 dias'], 'term_months' => 12 }
    assert JrcCrm::ContractTemplateSelection.match?(rules, { 'order_origins' => 'renewal', 'payment_conditions' => '30 dias', 'term_months' => 12 })
    refute JrcCrm::ContractTemplateSelection.match?(rules, { 'order_origins' => 'direct_sale' })
    refute JrcCrm::ContractTemplateSelection.match?({ 'unrecognized' => 1 }, {})
    assert_nil JrcCrm::ContractTemplateSelection.select([Template.new(1, rules)], {})
  end
  def upload(bytes: "%PDF-1.7\n/Type /Page\nstartxref\n0\n%%EOF", type: 'application/pdf', name: 'assinado.pdf', size: nil)
    FileUpload.new(StringIO.new(bytes), size || bytes.bytesize, type, name)
  end
  def test_pdf_validation_rewinds_upload_for_storage
    file = upload
    assert JrcCrm::SignedPdfValidation.validate!(file)
    assert_equal 0, file.tempfile.pos
  end
  def test_missing_invalid_or_oversized_signed_document_is_rejected
    [nil, upload(bytes: 'HTML'), upload(type: 'image/png'), upload(name: 'fake.txt'),
     upload(size: 21 * 1024 * 1024), upload(bytes: '')].each do |file|
      assert_raises(ArgumentError) { JrcCrm::SignedPdfValidation.validate!(file) }
      assert_equal 0, file.tempfile.pos if file
    end
  end
  def test_pdf_requires_ending_and_cross_reference
    ["%PDF-1.7 /Type /Page", "%PDF-1.7 /Type /Page %%EOF"].each do |bytes|
      assert_raises(ArgumentError) { JrcCrm::SignedPdfValidation.validate!(upload(bytes: bytes)) }
    end
  end
end
