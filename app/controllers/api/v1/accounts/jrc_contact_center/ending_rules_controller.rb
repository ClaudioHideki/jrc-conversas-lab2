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

  # Explicit review of the current version. This writes prospective readiness
  # only; it neither executes a destination nor replays earlier attendances.
  def activate
    document = write_document!(%w[expected_revision request_key rule_code])
    receipt = JrcContactCenter::EndingActions::ActivateRule.new(
      account: Current.account, member: Current.account_user, rule_code: document.fetch('rule_code'),
      request_key: document.fetch('request_key'), expected_revision: document.fetch('expected_revision')
    ).call
    item = { id: receipt.id.to_s, rule_code: receipt.rule_code, version_id: receipt.version_id.to_s,
             activated_at: receipt.created_at.iso8601, prospective_only: true }
    render_private(item: item, reviewed_revision: document.fetch('expected_revision'))
  end

  def readiness
    document = JrcContactCenter::EndingActions::ReadinessStatus.new(
      account: Current.account, member: Current.account_user, rule_code: params[:rule_code], expected_revision: params[:expected_revision]
    ).call
    render_private(document)
  end

  private

  # Read the bounded JSON document directly so Rails deep-munging cannot discard
  # null/false array entries and silently change the proposed private rule.
  def write_document!(expected_keys = %w[expected_revision private_rule])
    raw = request.raw_post
    valid = request.media_type == 'application/json' && raw.bytesize.between?(1, 262_144)
    raise JrcContactCenter::OperationError, 'invalid_ending_automation_rule' unless valid

    document = ActiveSupport::JSON.decode(raw)
    valid = document.is_a?(Hash) && document.keys.sort == expected_keys
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
