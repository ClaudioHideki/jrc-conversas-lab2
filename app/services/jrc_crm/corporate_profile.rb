class JrcCrm::CorporateProfile
  KEY = 'corporate_profile'.freeze
  TEXT_FIELDS = %w[legal_name legal_representative authorization_reference].freeze
  AUTHORITY_FIELDS = %w[commercial_gratuity_principal_id commercial_gratuity_substitute_id
                        financial_gratuity_principal_id financial_gratuity_substitute_id].freeze
  FIELDS = (TEXT_FIELDS + AUTHORITY_FIELDS + %w[fiscal_address_id responsible_account_user_ids]).freeze
  AUTHORITY_PROFILE_FIELDS = (AUTHORITY_FIELDS + %w[authorization_reference]).freeze

  def self.read(company)
    company.custom_attributes.fetch(KEY, {}).slice(*FIELDS)
  end

  def self.merge!(company:, account:, attributes:)
    data = normalize(account: account, attributes: attributes, fields: FIELDS)
    if data.key?('responsible_account_user_ids')
      ids = data['responsible_account_user_ids']
      raise ArgumentError, 'INVALID_CORPORATE_PROFILE' unless ids.is_a?(Array) && ids.length <= 32

      data['responsible_account_user_ids'] = ids.map { |id| member_id(account, id) }.uniq
    end
    if data['fiscal_address_id'].present?
      data['fiscal_address_id'] = company.addresses.where(account_id: account.id).find(data['fiscal_address_id']).id
    end
    profile = validate_reference!(read(company).merge(data))
    company.custom_attributes.merge(KEY => profile)
  end

  def self.authorities(account:, current:, attributes:)
    validate_reference!(current.merge(normalize(account: account, attributes: attributes, fields: AUTHORITY_PROFILE_FIELDS)))
  end

  def self.normalize(account:, attributes:, fields:)
    data = attributes.to_h.stringify_keys
    raise ArgumentError, 'INVALID_CORPORATE_PROFILE' unless (data.keys - fields).empty?

    data.each { |key, value| data[key] = normalized_value(account, key, value) }
    data
  end

  def self.normalized_value(account, key, value)
    return normalized_text(value) if TEXT_FIELDS.include?(key)
    return value unless AUTHORITY_FIELDS.include?(key)

    value.blank? ? nil : member_id(account, value)
  end

  def self.normalized_text(value)
    raise ArgumentError, 'INVALID_CORPORATE_PROFILE' unless value.nil? || (value.is_a?(String) && value.length <= 255)

    value&.strip.presence
  end

  def self.member_id(account, id)
    raise ArgumentError, 'INVALID_CORPORATE_PROFILE' unless id.to_s.match?(/\A[1-9]\d*\z/)

    member = account.account_users.includes(:user).find(id)
    raise ArgumentError, 'INACTIVE_CORPORATE_MEMBER' unless member.user.active_for_authentication?

    member.id
  end

  def self.validate_reference!(profile)
    if AUTHORITY_FIELDS.any? { |key| profile[key].present? } && profile['authorization_reference'].blank?
      raise ArgumentError, 'AUTHORITY_AUTHORIZATION_REQUIRED'
    end

    profile
  end
end
