require 'digest'

class RelationshipSurveysController < ActionController::Base
  protect_from_forgery with: :exception
  before_action :survey
  rescue_from ActiveRecord::RecordInvalid do |error|
    render plain: error.record.errors.full_messages.join('. '), status: :unprocessable_entity
  end
  rescue_from ArgumentError do |_error|
    render plain: 'Verifique as respostas conforme as perguntas publicadas.', status: :unprocessable_entity
  end

  def show
    render :show
  end

  def update
    answers = params[:answers].present? ? params.require(:answers).to_unsafe_h : { 'score' => params.require(:score) }
    JrcRelationship::SurveyResponse.new(@survey).call(answers: answers, comment: params[:comment])
    render plain: @survey.definition_snapshot.dig('settings', 'thank_you').presence || 'Obrigado pela resposta.'
  end

  private

  def survey
    token = params[:token].to_s
    @survey = if token.match?(/\A[0-9a-f]{64}\z/)
                JrcRelationship::Survey.find_by!(token_digest: Digest::SHA256.hexdigest(token))
              else
                JrcRelationship::Survey.find_signed(token.first(4096), purpose: :relationship_survey) || raise(ActiveRecord::RecordNotFound)
              end
    raise ActiveRecord::RecordNotFound unless @survey.account.active? && @survey.account.feature_enabled?('jrc_customer_master') && @survey.account.feature_enabled?('jrc_relationship') && @survey.responded_at.nil? && @survey.expires_at > Time.current

    validate_dispatch_state!
  end

  def validate_dispatch_state!
    raise ActiveRecord::RecordNotFound if @survey.source_type.present? && %w[available sent delivered].exclude?(@survey.status)
  end
end
