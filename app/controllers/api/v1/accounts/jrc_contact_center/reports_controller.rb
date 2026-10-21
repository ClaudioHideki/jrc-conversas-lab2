# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::ReportsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def summary
    authorize_contact_center!(:reports?)
    metrics = JrcContactCenter::MetricsSummary.from_params(scope: contact_center_access.daily_facts, params: params).call
    render json: base_payload.merge(metrics: metrics)
  rescue ArgumentError
    render json: base_payload.merge(error: 'invalid_report_range'), status: :unprocessable_entity
  end
end
