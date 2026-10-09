class JrcRelationship::SurveyWhatsappTemplate
  def initialize(survey:, conversation:, url:, origin:, params:)
    @survey = survey
    @conversation = conversation
    @url = url
    @origin = origin
    @params = params
  end

  def validate!
    raise ArgumentError, 'Survey template inbox belongs to another account' unless @conversation.account_id == @survey.account_id
    raise ArgumentError, 'Survey template parameters are invalid' unless valid_url?

    selection = JrcRelationship::SurveyTemplateSelection.new(account_id: @survey.account_id, inbox: @conversation.inbox, params: @params)
    texts = selection.body_texts
    raise ArgumentError, 'The template must contain the exact signed survey link' unless texts.any? { |text| text.to_s.include?(@url) }

    @params
  end

  def self.valid_message?(survey, message)
    params = message.additional_attributes['template_params']
    return false if params.blank? || survey.metadata['survey_link_url'].blank? || survey.metadata['survey_link_origin'].blank?
    return false unless message.content_attributes['relationship_survey_link'] == survey.metadata['survey_link_url'] &&
                        message.content_attributes['relationship_survey_link_origin'] == survey.metadata['survey_link_origin']

    new(survey: survey, conversation: message.conversation, url: survey.metadata['survey_link_url'],
        origin: survey.metadata['survey_link_origin'], params: params).validate!
    JrcRelationship::SurveyRuleTemplate.valid_message?(survey, message)
  rescue ArgumentError, ActiveRecord::RecordNotFound, ActiveSupport::MessageVerifier::InvalidSignature
    false
  end

  private

  def valid_url?
    uri = URI.parse(@url.to_s)
    origin = URI.parse(@origin.to_s)
    return false unless valid_uri?(uri)
    return false unless [uri.scheme, uri.host, uri.port] == [origin.scheme, origin.host, origin.port]
    return false unless uri.path.start_with?('/jrc/relacionamento/pesquisas/')

    JrcRelationship::Survey.find_signed!(uri.path.split('/').last, purpose: :relationship_survey).id == @survey.id
  rescue URI::InvalidURIError
    false
  end

  def valid_uri?(uri)
    %w[http https].include?(uri.scheme) && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
  end
end
