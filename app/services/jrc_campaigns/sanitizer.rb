require 'set'

class JrcCampaigns::Sanitizer
  def initialize(account:, user:, name:, entries:, include_channel_statuses: true)
    @account = account
    @user = user
    @name = name
    @entries = entries
    @include_channel_statuses = include_channel_statuses
  end

  def perform
    JrcCampaigns::SanitizedList.transaction do
      list = account.jrc_campaign_sanitized_lists.create!(name: name, created_by: user)
      seen_phones = Set.new
      seen_emails = Set.new
      stats = Hash.new(0)

      entries.each do |raw|
        data = raw.respond_to?(:to_h) ? raw.to_h.with_indifferent_access : { phone: raw.to_s }
        phone = data[:phone] || data[:telefone] || data[:phone_number] || data[:celular]
        email = data[:email] || data[:e_mail]
        normalized_phone = JrcCampaigns::PhoneNormalizer.call(phone)
        normalized_email = JrcCampaigns::EmailNormalizer.call(email)
        phone_status, phone_reason = classify_phone(normalized_phone, seen_phones)
        email_status, email_reason = classify_email(normalized_email, seen_emails)
        status, reason = overall_status(phone_status, email_status, phone_reason, email_reason)

        seen_phones << normalized_phone if normalized_phone.present?
        seen_emails << normalized_email if normalized_email.present?
        stats[status] += 1
        stats['valid_phone'] += 1 if phone_status == 'valid'
        stats['valid_email'] += 1 if email_status == 'valid'
        metadata = data.except(:name, :nome, :phone, :telefone, :phone_number, :celular, :email, :e_mail)
        metadata = metadata.merge('phone_status' => phone_status, 'email_status' => email_status) if @include_channel_statuses

        list.entries.create!(
          name: data[:name] || data[:nome],
          phone_number: phone,
          normalized_phone: normalized_phone,
          email: email,
          normalized_email: normalized_email,
          status: status,
          reason: reason,
          metadata: metadata
        )
      end

      list.update!(stats: stats.merge('total' => entries.size))
      list
    end
  end

  private

  attr_reader :account, :user, :name, :entries

  def blacklisted_phones
    @blacklisted_phones ||= account.jrc_campaign_blacklists.pluck(:phone_number).to_set
  end

  def classify_phone(normalized, seen)
    return ['invalid', 'Telefone vazio ou inválido'] unless normalized&.match?(/\A\+[1-9]\d{7,14}\z/)
    return ['duplicate', 'Telefone duplicado na lista'] if seen.include?(normalized)
    return ['blacklisted', 'Telefone presente na blacklist'] if blacklisted_phones.include?(normalized)

    ['valid', nil]
  end

  def classify_email(normalized, seen)
    return ['invalid', 'E-mail vazio ou inválido'] if normalized.blank?
    return ['duplicate', 'E-mail duplicado na lista'] if seen.include?(normalized)

    ['valid', nil]
  end

  def overall_status(phone_status, email_status, phone_reason, email_reason)
    return ['valid', nil] if phone_status == 'valid' || email_status == 'valid'
    return ['blacklisted', phone_reason] if phone_status == 'blacklisted' && email_status == 'invalid'
    return ['duplicate', [phone_reason, email_reason].compact.join('; ')] if [phone_status, email_status].include?('duplicate')

    ['invalid', [phone_reason, email_reason].compact.join('; ')]
  end
end
