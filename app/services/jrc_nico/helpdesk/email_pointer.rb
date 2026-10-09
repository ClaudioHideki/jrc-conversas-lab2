# frozen_string_literal: true

class JrcNico::Helpdesk::EmailPointer
  def self.url(source)
    uri = URI.parse(ENV.fetch('FRONTEND_URL', ''))
    raise ArgumentError, 'Configured application origin required' unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo

    uri.path = "#{uri.path.to_s.sub(%r{/$}, '')}/app/accounts/#{source.account_id}/nico-helpdesk"
    uri.query = source.is_a?(JrcNico::Helpdesk::Event) ? nil : URI.encode_www_form(report_id: source.id)
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    raise ArgumentError, 'Configured application origin required', cause: nil
  end

  def self.subject(source)
    key = source.is_a?(JrcNico::Helpdesk::Event) ? 'event_mailer_subject' : 'mailer_subject'
    I18n.t("jrc_nico.helpdesk.#{key}", locale: :en)
  end
end
