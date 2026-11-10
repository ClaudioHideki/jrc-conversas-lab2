require 'openssl'

# A protected extension of the native Contact, not another person registry.
# Registration of an identifier never constitutes proof of signing authority.
class JrcCustomers::SigningIdentity < ApplicationRecord
  self.table_name = 'jrc_customer_signing_identities'
  encrypts :personal_tax_identifier, support_unencrypted_data: false
  self.filter_attributes += %i[personal_tax_identifier lookup_digest]
  attr_readonly :account_id, :created_by_id
  belongs_to :account
  belongs_to :contact
  belongs_to :created_by, class_name: 'User'
  validates :contact_id, :lookup_digest, uniqueness: { scope: :account_id }
  validates :revision, numericality: { only_integer: true, greater_than: 0 }
  validates :personal_tax_identifier, presence: true
  before_validation :normalize_identifier
  validate :valid_identifier
  validate do
    errors.add(:contact, 'must belong to account') unless contact&.account_id == account_id
  end
  validate(on: :create) do
    errors.add(:created_by, 'must belong to account') unless AccountUser.exists?(account_id: account_id, user_id: created_by_id)
  end

  def self.digest_for(account_id:, value:)
    return unless account_id.is_a?(Integer) && account_id.positive?

    normalized = JrcCustomers::TaxIdentifier.normalize(value)
    return unless normalized && JrcCustomers::TaxIdentifier.cpf_valid?(normalized)

    key = Rails.application.key_generator.generate_key('jrc-customer-personal-identifier-index-v1', 32)
    OpenSSL::HMAC.hexdigest('SHA256', key, "#{Integer(account_id)}:#{normalized}")
  end

  def masked_identifier
    value = personal_tax_identifier
    "***.***.***-#{value[-2, 2]}" if value.present?
  end

  def serializable_hash(_options = nil)
    { 'contact_id' => contact_id, 'revision' => revision, 'personal_tax_identifier_masked' => masked_identifier,
      'updated_at' => updated_at }
  end

  private

  def normalize_identifier
    self.personal_tax_identifier = JrcCustomers::TaxIdentifier.normalize(personal_tax_identifier)
    self.lookup_digest = self.class.digest_for(account_id: account_id, value: personal_tax_identifier)
  end

  def valid_identifier
    value = personal_tax_identifier
    errors.add(:personal_tax_identifier, :invalid) unless value.present? && JrcCustomers::TaxIdentifier.cpf_valid?(value)
  end
end
