# frozen_string_literal: true

# Only the reviewed HTTPS address and existing SafeFetch transport are used.
# This contract never adds provider credentials or renders a destination URL.
class JrcRelationship::PlaybookFlowDeliveryGuard
  def initialize(reference)
    @reference = reference
  end

  def authorize!(type, data)
    raise ArgumentError, 'playbook_flow_effect_not_approved' unless @reference.policy.effect_allowed?(type)
    raise Pundit::NotAuthorizedError unless ConversationPolicy.new(@reference.context.to_h, @reference.conversation).show?
    raise ArgumentError, 'playbook_flow_public_transport_required' if SafeFetch.allow_private_network?

    allowed_fields = type == 'media' ? %w[url text] : %w[url body]
    raise ArgumentError, 'playbook_flow_delivery_fields_invalid' unless (data.keys - allowed_fields).empty?

    url = data.fetch('url')
    raise ArgumentError, 'playbook_flow_delivery_url_invalid' unless url.is_a?(String)

    uri = URI.parse(url)
    valid = url.is_a?(String) && url.bytesize <= 2048 && uri.is_a?(URI::HTTPS) && uri.host.present? &&
            uri.userinfo.nil? && uri.fragment.nil? && !url.include?('{{')
    raise ArgumentError, 'playbook_flow_delivery_url_invalid' unless valid

    data.except('url').each_value do |value|
      raise ArgumentError, 'playbook_flow_delivery_body_invalid' unless value.nil? || (value.is_a?(String) && value.bytesize <= 10_000)
    end
    true
  rescue URI::InvalidURIError
    raise ArgumentError, 'playbook_flow_delivery_url_invalid'
  end
end
