# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::TeamSupervisionsController < Api::V1::Accounts::JrcContactCenter::BaseController
  wrap_parameters false
  before_action -> { response.headers['Cache-Control'] = 'no-store' }
  before_action -> { supervisions.authorize! }

  def show
    render json: base_payload.merge(item: supervisions.present(supervisions.team(params[:id])))
  end

  def update
    valid = (request.request_parameters.keys - %w[supervision expected_revision]).empty?
    raise JrcContactCenter::OperationError, 'invalid_team_supervision' unless valid

    item = supervisions.update!(id: params[:id], attributes: supervision_attributes, expected: params[:expected_revision])
    render json: base_payload.merge(item: item)
  end

  def candidates
    record = supervisions.team(params[:id])
    params[:page] = 1 if params[:page].blank?
    params[:per_page] = params.fetch(:per_page, 20).to_i.clamp(1, 20)
    render json: list_payload(candidate_members.order(:id)) { |member| supervisions.candidate(record, member) }
  end

  private

  def candidate_members
    members = Current.account.account_users.includes(:user, :custom_role)
    return members if params[:q].blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.first(100))}%"
    members.joins(:user).where('users.name ILIKE ?', pattern)
  end

  def supervisions
    @supervisions ||= JrcContactCenter::TeamSupervisions.new(context: pundit_user)
  end

  def supervision_attributes
    values = params.require(:supervision)
    valid = values.respond_to?(:permit) && (values.keys - JrcContactCenter::TeamSupervisionInput::FIELDS).empty?
    raise JrcContactCenter::OperationError, 'invalid_team_supervision' unless valid

    values.permit(:primary_account_user_id, additional_account_user_ids: []).to_h
  end
end
