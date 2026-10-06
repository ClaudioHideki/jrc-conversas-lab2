require 'digest'

class RelationshipSurveysController < ActionController::Base
  protect_from_forgery with: :exception
  before_action :survey
  rescue_from ActiveRecord::RecordInvalid do |error|
    render plain: error.record.errors.full_messages.join('. '), status: :unprocessable_entity
  end

  def show
    render inline: '<!doctype html><html lang="pt-BR"><head><meta charset="UTF-8"><title>Pesquisa de relacionamento</title></head><body><h1>Pesquisa de relacionamento</h1><p><%= @survey.metadata["question"] %></p><%= form_with url: request.path do %><label>Nota de 0 a 10 <%= number_field_tag :score, nil, min: 0, max: 10, required: true %></label><label>Comentário <%= text_area_tag :comment, nil, maxlength: 4000 %></label><%= submit_tag "Enviar resposta" %><% end %></body></html>'
  end

  def update
    @survey.with_lock do
      raise ActiveRecord::RecordNotFound if @survey.responded_at || @survey.expires_at <= Time.current
      @survey.update!(score: params.require(:score), comment: params[:comment], responded_at: Time.current)
      JrcCustomers::Audit.record!(account: @survey.account, actor: nil, resource: @survey, event_type: 'relationship_updated', metadata: { action: 'survey_responded', assignment_id: @survey.assignment_id })
    end
    render plain: 'Obrigado pela resposta.'
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
  end
end
