class JrcCampaigns::EmailNormalizer
  def self.call(value)
    email = value.to_s.strip.downcase
    return if email.blank? || !email.match?(Devise.email_regexp)

    email
  end
end
