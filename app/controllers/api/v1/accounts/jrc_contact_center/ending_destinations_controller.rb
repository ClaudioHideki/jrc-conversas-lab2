# frozen_string_literal: true

# Existing Call Center authentication, native scopes and ledger services. These
# commands register selected durable intents; a 202 never claims a native effect.
class Api::V1::Accounts::JrcContactCenter::EndingDestinationsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    response.headers['Cache-Control'] = 'no-store'
    result = JrcContactCenter::EndingActions::ManualDestinationPage.new(
      account: Current.account, member: Current.account_user, qualification_id: qualification_identity, page: params.fetch(:page, 1)
    ).call
    render json: base_payload.merge(result)
  end

  def create
    input = reviewed_document!(%w[destination_kind origin_id request_key review rule_code])
    validate_manual_action!(input)
    row = JrcContactCenter::EndingActions::RequestManualDestination.new(
      account: Current.account, member: Current.account_user, qualification_id: qualification_identity,
      origin_id: input.fetch('origin_id'), rule_code: input.fetch('rule_code'), destination_kind: input.fetch('destination_kind'),
      request_key: input.fetch('request_key'), review: input.fetch('review')
    ).call
    render_recorded(row)
  end

  def retry_attempt
    input = reviewed_document!(%w[request_key review])
    row = JrcContactCenter::EndingActions::RequestDestinationRetry.new(
      account: Current.account, member: Current.account_user, qualification_id: qualification_identity,
      attempt_id: attempt_identity, request_key: input.fetch('request_key'), review: input.fetch('review')
    ).call
    render_recorded(row)
  end

  def resume_pending
    input = reviewed_document!(%w[review])
    row = JrcContactCenter::EndingActions::ResumeDestinationDelivery.new(
      account: Current.account, member: Current.account_user, qualification_id: qualification_identity,
      attempt_id: attempt_identity, review: input.fetch('review')
    ).call
    render_recorded(row)
  end

  private

  def validate_manual_action!(input)
    input['origin_id'] = JrcServiceDesk::Input.id(input.fetch('origin_id'))
    code = input.fetch('rule_code')
    valid = valid_rule_code?(code)
    valid &&= %w[project_task crm service_desk].include?(input.fetch('destination_kind'))
    raise JrcContactCenter::OperationError, 'invalid_ending_pending_review' unless valid
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_ending_pending_review'
  end

  def valid_rule_code?(code)
    code.is_a?(String) && code.valid_encoding? && code.exclude?("\u0000") && code.strip.present? && code.length <= 100
  end

  def attempt_identity
    JrcServiceDesk::Input.id(params[:attempt_id])
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_ending_pending_review'
  end

  def qualification_identity
    JrcServiceDesk::Input.id(params[:qualification_id])
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_ending_history_request'
  end

  def reviewed_document!(fields)
    raw = request.raw_post
    valid = request.media_type == 'application/json' && raw.bytesize.between?(1, 4096)
    raise JrcContactCenter::OperationError, 'invalid_ending_pending_review' unless valid

    input = ActiveSupport::JSON.decode(raw)
    valid = input.is_a?(Hash) && input.keys.sort == fields
    raise JrcContactCenter::OperationError, 'invalid_ending_pending_review' unless valid

    input
  rescue JSON::ParserError
    raise JrcContactCenter::OperationError, 'invalid_ending_pending_review'
  end

  def render_recorded(row)
    response.headers['Cache-Control'] = 'no-store'
    render json: base_payload.merge(
      qualification_id: qualification_identity.to_s, ledger: 'typed', attempt_id: row.id.to_s,
      request_id: row.request_key, status: 'accepted', execution_confirmed: false
    ), status: :accepted
  end
end
