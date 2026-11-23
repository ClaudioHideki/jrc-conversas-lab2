# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::EndingRulesController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    document = JrcContactCenter::EndingActions::VisibleRules.new(
      account: Current.account, member: Current.account_user, filters: params.permit(:q, :status, :reason_code, :rule_code, :page, :per_page).to_h
    ).call
    render_private(document)
  end

  def source_context
    document = JrcContactCenter::EndingActions::SourceContext.new(
      account: Current.account, member: Current.account_user, queue_id: params[:queue_id]
    ).call
    render_private(item: document)
  end

  def create
    document = write_document!
    result = JrcContactCenter::EndingActions::ConfigureRule.new(
      account: Current.account, member: Current.account_user, input: document.fetch('private_rule'),
      expected_revision: document.fetch('expected_revision')
    ).call
    render_private(item: result.fetch(:rule), revision: result.fetch(:revision), execution_available: false, configuration_only: true)
  end

  private

  # Read the bounded JSON document directly so Rails deep-munging cannot discard
  # null/false array entries and silently change the proposed private rule.
  def write_document!
    raw = request.raw_post
    valid = request.media_type == 'application/json' && raw.bytesize.between?(1, 262_144)
    raise JrcContactCenter::OperationError, 'invalid_ending_automation_rule' unless valid

    document = ActiveSupport::JSON.decode(raw)
    valid = document.is_a?(Hash) && document.keys.sort == %w[expected_revision private_rule]
    raise JrcContactCenter::OperationError, 'invalid_ending_automation_rule' unless valid

    document
  rescue JSON::ParserError
    raise JrcContactCenter::OperationError, 'invalid_ending_automation_rule'
  end

  def render_private(document)
    response.headers['Cache-Control'] = 'no-store'
    render json: base_payload.merge(document)
  end
end
