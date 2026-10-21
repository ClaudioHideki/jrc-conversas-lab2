class JrcCampaigns::TemplateRenderer
  def initialize(recipient:, inbox:)
    @recipient = recipient
    @inbox = inbox
  end

  def render(value)
    case value
    when Hash then value.transform_values { |item| render(item) }
    when Array then value.map { |item| render(item) }
    when String then Liquid::Template.parse(apply_spintax(value)).render(context)
    else value
    end
  rescue Liquid::Error
    value
  end

  private

  attr_reader :recipient, :inbox

  def apply_spintax(value)
    value.gsub(/\{([^{}|]+(?:\|[^{}|]+)+)\}/) do
      Regexp.last_match(1).split('|').sample
    end
  end

  def context
    contact = recipient.contact
    email = recipient.respond_to?(:email) ? recipient.email : contact&.email
    {
      'nome' => recipient.name.to_s,
      'telefone' => recipient.phone_number.to_s,
      'email' => email.to_s,
      'contact' => {
        'name' => recipient.name.to_s,
        'phone_number' => recipient.phone_number.to_s,
        'email' => email.to_s
      },
      'inbox' => { 'name' => inbox.name.to_s },
      'account' => { 'name' => recipient.campaign.account.name.to_s }
    }
  end
end
