require 'minitest/autorun'
require 'ostruct'
module JrcBackoffice; end
module JrcCustomers; end
require_relative '../../app/services/jrc_customers/tax_identifier'
require_relative '../../app/services/jrc_backoffice/requirement_catalog'

class RequirementCustomerKindTest < Minitest::Test
  def classify(id)
    request = OpenStruct.new(contact: OpenStruct.new(company: OpenStruct.new(tax_id: id)))
    JrcBackoffice::RequirementCatalog.customer_kind(request)
  end
  def test_numeric_company
    assert_equal 'company', classify('11.222.333/0001-81')
  end
  def test_individual
    assert_equal 'individual', classify('111.444.777-35')
  end
  def test_native_alphanumeric_company
    first = '12ABC34501DE'.chars.map { |c| c.ord - 48 }
    a = JrcCustomers::TaxIdentifier.checksum(first, [5,4,3,2,9,8,7,6,5,4,3,2])
    b = JrcCustomers::TaxIdentifier.checksum(first + [a], [6,5,4,3,2,9,8,7,6,5,4,3,2])
    assert_equal 'company', classify("12ABC34501DE#{a}#{b}")
  end
  def test_invalid_company_stays_unknown
    assert_nil classify('11222333000180')
  end
  def test_invalid_individual_stays_unknown
    assert_nil classify('11144477734')
  end
  def test_missing_identifier_stays_unknown
    assert_nil classify(nil)
    assert_nil classify('')
  end
  def test_no_contact_does_not_bypass_conditional_rules
    assert_nil JrcBackoffice::RequirementCatalog.customer_kind(OpenStruct.new(contact: nil))
  end
end
