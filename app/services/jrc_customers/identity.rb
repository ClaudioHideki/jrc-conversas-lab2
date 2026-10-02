require 'uri'

# Directory matching only. Never replaces ContactInbox.source_id/HMAC or
# authenticates a person merely because a telephone/email matches.
module JrcCustomers::Identity
  EMAIL_KINDS = %w[email corporate_email alternate_email].freeze
  PHONE_KINDS = %w[phone mobile whatsapp whatsapp_business].freeze
  module_function

  def email(value)
    candidate = value.to_s.strip.downcase
    return nil unless candidate.match?(URI::MailTo::EMAIL_REGEXP)

    candidate
  end

  def phone(value, country: nil)
    raw = value.to_s.strip
    return nil unless raw.match?(/\A(?:\+|00)?[0-9().\s-]+\z/)

    digits = raw.gsub(/[^0-9]/, '')
    digits = digits.delete_prefix('00') if raw.start_with?('00')
    if !raw.start_with?('+', '00') && country == 'BR' && [10, 11].include?(digits.length)
      digits = "55#{digits}"
    elsif !raw.start_with?('+', '00') && digits.length < 12
      return nil
    end
    return nil unless digits.match?(/\A[1-9][0-9]{7,14}\z/)

    "+#{digits}"
  end

  def point(kind, value)
    return email(value) if EMAIL_KINDS.include?(kind)
    return phone(value) if PHONE_KINDS.include?(kind)
    return value.to_s.strip if kind == 'extension' && value.to_s.strip.match?(/\A[0-9]{2,6}\z/)

    nil
  end
end
