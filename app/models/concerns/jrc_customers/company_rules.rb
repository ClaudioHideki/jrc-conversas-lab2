module JrcCustomers::CompanyRules
  extend ActiveSupport::Concern
  RELATIONSHIPS = %w[prospect lead customer former_customer partner supplier internal other].freeze
  PERSON_KINDS = %w[organization individual].freeze
  SIZES = %w[mei me epp medium large].freeze
  SOURCES = %w[referral inbound outbound website campaign event partner import manual other].freeze

  included do
    belongs_to :created_by, class_name: 'User', optional: true
    belongs_to :updated_by, class_name: 'User', optional: true

    before_validation :normalize_master_attributes, if: :master_columns?
    validates :person_kind, inclusion: { in: PERSON_KINDS }, if: :master_columns?
    validates :relationship_type, inclusion: { in: RELATIONSHIPS }, if: :master_columns?
    validates :tax_id, uniqueness: { scope: :account_id }, allow_blank: true, if: :master_columns?
    validates :customer_code, uniqueness: { scope: :account_id }, format: { with: /\AEMP-\d{6,}\z/ }, allow_blank: true,
                              if: -> { master_columns? && has_attribute?(:customer_code) }
    validate :validate_master_links, if: :master_columns?
    validate :validate_master_tax_identifier, if: :master_columns?
    validate :validate_master_classifications, if: :master_columns?
    validate :validate_master_taxonomies, if: :master_columns?
    after_save :synchronize_legacy_company_fields, if: :master_columns?
  end

  private

  def master_columns?
    has_attribute?(:relationship_type) && (is_a?(JrcCustomers::Company) || account&.feature_enabled?('jrc_customer_master'))
  end

  def normalize_master_attributes
    self.tax_id = JrcCustomers::TaxIdentifier.normalize(tax_id)
    self.email = email.to_s.strip.downcase.presence
    self.domain = domain.to_s.strip.downcase.presence
    self.segment = segment.to_s.strip.presence if has_attribute?(:segment)
    self.size = size.to_s.strip.presence if has_attribute?(:size)
    self.source = source.to_s.strip.presence if has_attribute?(:source)
    self.relationship_tags = normalized_string_list(relationship_tags) if has_attribute?(:relationship_tags)
    self.tags = normalized_string_list(tags) if has_attribute?(:tags)
  end

  def normalized_string_list(value)
    Array(value).filter_map { |item| item.to_s.strip.presence }.uniq.first(50)
  end

  def validate_master_tax_identifier
    errors.add(:tax_id, 'CPF/CNPJ invalido') unless JrcCustomers::TaxIdentifier.valid?(tax_id, person_kind: person_kind)
    errors.add(:email, 'invalido') if email.present? && JrcCustomers::Identity.email(email).nil?
  end

  def validate_master_classifications
    if has_attribute?(:relationship_tags)
      invalid = Array(relationship_tags) - RELATIONSHIPS
      errors.add(:relationship_tags, 'contains an invalid relationship') if invalid.any?
      errors.add(:relationship_tags, 'must not repeat the primary relationship') if Array(relationship_tags).include?(relationship_type)
    end
    errors.add(:tags, 'supports at most 50 tags') if has_attribute?(:tags) && Array(tags).size > 50
  end

  def validate_master_taxonomies
    if will_save_change_to_size? && size.present? && !SIZES.include?(size)
      errors.add(:size, 'must use a configured company size')
    end
    if will_save_change_to_source? && source.present? && !SOURCES.include?(source)
      errors.add(:source, 'must use a configured origin')
    end
    return unless will_save_change_to_segment? && segment.present? && JrcCustomers::Taxonomy.table_exists?

    configured = JrcCustomers::Taxonomy.where(account_id: account_id, kind: 'segment', active: true).exists?(name: segment)
    errors.add(:segment, 'must use an active configured segment') unless configured
  end

  def validate_master_links
    errors.add(:owner_id, 'must belong to this account') if owner_id.present? && !account.users.exists?(id: owner_id)
    return if parent_company_id.blank?

    seen = [id].compact
    parent_id = parent_company_id
    while parent_id
      if seen.include?(parent_id)
        errors.add(:parent_company_id, 'cannot create a hierarchy cycle')
        return
      end
      if seen.length >= 100
        errors.add(:parent_company_id, 'hierarchy exceeds 100 levels')
        return
      end
      seen << parent_id
      parent = JrcCustomers::Company.where(account_id: account_id).find_by(id: parent_id)
      unless parent
        errors.add(:parent_company_id, 'must belong to this account')
        return
      end
      parent_id = parent.parent_company_id
    end
  end

  def synchronize_legacy_company_fields
    return unless account.feature_enabled?('jrc_customer_master')

    # Legacy IDs remain usable; these rows are compatibility projections, not
    # another source for new customer registrations. Keep legacy JSON intact.
    JrcCrm::Organization.where(account_id: account_id, company_id: id).update_all(
      name: name, domain: domain, description: description, phone: phone_number,
      website: website, active: active, owner_id: owner_id, updated_at: updated_at
    )
  end
end
