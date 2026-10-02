# Runs WITHOUT Rails or database: ruby test/jrc_customers/identity_pure_test.rb
require 'minitest/autorun'
module JrcCustomers; end
require_relative '../../app/services/jrc_customers/identity'
require_relative '../../app/services/jrc_customers/tax_identifier'

class CustomerIdentityPureTest < Minitest::Test
  Identity = JrcCustomers::Identity
  Tax = JrcCustomers::TaxIdentifier

  def test_email_normalization
    assert_equal 'ana@example.test', Identity.email(' ANA@EXAMPLE.TEST ')
  end
  def test_invalid_emails
    [nil, '', 'name', 'a b@example.test', 'a@'].each { |value| assert_nil Identity.email(value) }
  end
  def test_email_plus_alias_preserved
    assert_equal 'ana+sales@example.test', Identity.email('ana+sales@example.test')
  end
  def test_international_phone_punctuation
    assert_equal '+5511999999999', Identity.phone('+55 (11) 99999-9999')
  end
  def test_explicit_br_country
    assert_equal '+5511999999999', Identity.phone('(11) 99999-9999', country: 'BR')
  end
  def test_explicit_br_landline
    assert_equal '+551133334444', Identity.phone('(11) 3333-4444', country: 'BR')
  end
  def test_ambiguous_local_phone_not_guessed
    assert_nil Identity.phone('11999999999')
    assert_nil Identity.phone('2125550100', country: 'US')
  end
  def test_international_prefix_00
    assert_equal '+442071838750', Identity.phone('00442071838750')
  end
  def test_explicit_us_country_code
    assert_equal '+12125550100', Identity.phone('+1 (212) 555-0100')
  end
  def test_legacy_digits_with_full_country_code
    assert_equal '+5511999999999', Identity.phone('5511999999999')
  end
  def test_invalid_phones
    [nil, '', 'abc', '+00', '+5511;DROP', '+55 11 99999x9999', '+1234567890123456', '+0123456789'].each do |value|
      assert_nil Identity.phone(value)
    end
  end
  def test_phone_does_not_treat_extension_as_mobile
    assert_nil Identity.phone('1596')
  end
  def test_extension_retains_leading_zero
    assert_equal '01596', Identity.point('extension', ' 01596 ')
  end
  def test_bad_extensions
    ['', '1', '1234567', '1596@pabx', '+1596'].each { |value| assert_nil Identity.point('extension', value) }
  end
  def test_email_kinds_share_normalization
    Identity::EMAIL_KINDS.each { |kind| assert_equal 'ana@example.test', Identity.point(kind, 'Ana@Example.Test') }
  end
  def test_whatsapp_is_an_additional_point_not_new_person
    Identity::PHONE_KINDS.each { |kind| assert_equal '+5511999999999', Identity.point(kind, '+55 11 99999-9999') }
  end
  def test_unknown_point_kind_rejected
    assert_nil Identity.point('source_id', 'whatsapp:5511999999999')
  end
  def test_tax_normalization
    assert_equal '11222333000181', Tax.normalize('11.222.333/0001-81')
    assert_equal '12ABC34501DE35', Tax.normalize('12.abc.345/01de-35')
  end
  def test_blank_tax_optional
    assert_nil Tax.normalize('  ')
    assert Tax.valid?(nil)
  end
  def test_numeric_cnpj
    assert Tax.valid?('11.222.333/0001-81', person_kind: 'organization')
    assert Tax.valid?('04.252.011/0001-10', person_kind: 'organization')
  end
  def test_alphanumeric_cnpj
    assert Tax.valid?('12.ABC.345/01DE-35', person_kind: 'organization')
  end
  def test_cnpj_check_digits_must_be_numeric
    refute Tax.valid?('12ABC34501DE3A', person_kind: 'organization')
  end
  def test_cnpj_wrong_checksums
    %w[11222333000182 12ABC34501DE36 00000000000000 11111111111111].each { |value| refute Tax.valid?(value, person_kind: 'organization') }
  end
  def test_valid_cpf
    assert Tax.valid?('529.982.247-25', person_kind: 'individual')
    assert Tax.valid?('111.444.777-35', person_kind: 'individual')
  end
  def test_cpf_repeated_and_wrong_checksums
    %w[00000000000 11111111111 52998224726 5299822472A].each { |value| refute Tax.valid?(value, person_kind: 'individual') }
  end
  def test_person_kind_does_not_accept_other_document
    refute Tax.valid?('11222333000181', person_kind: 'individual')
    refute Tax.valid?('52998224725', person_kind: 'organization')
  end
  def test_tax_arbitrary_characters_not_stripped_into_valid_id
    refute Tax.valid?('11@222333000181')
    refute Tax.valid?('<script>11222333000181')
  end
  def test_normalization_idempotent
    ['11.222.333/0001-81', '12.ABC.345/01DE-35', '529.982.247-25', nil].each do |value|
      assert_equal Tax.normalize(value).to_s, Tax.normalize(Tax.normalize(value)).to_s
    end
  end
end
