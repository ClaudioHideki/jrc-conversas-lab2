# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::UnitsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!
    units = search_records(contact_center_access.units).order(:kind, :name, :id)
    render json: list_payload(units) { |unit| serialize(unit) }
  end

  def show
    response.headers['Cache-Control'] = 'no-store'
    authorize_contact_center!(:access?)
    unit = contact_center_access.units.find(params[:id])
    render json: base_payload.merge(item: serialize(unit))
  end

  def create
    authorize_contact_center!(:configure?)
    unit = configuration_write.create!(JrcContactCenter::Unit) { unit_params }
    render json: base_payload.merge(item: serialize(unit)), status: :created
  end

  def update
    authorize_contact_center!(:configure?)
    unit = configuration_write.update!(contact_center_access.units, params[:id], **configuration_revision_options) { unit_params }
    render json: base_payload.merge(item: serialize(unit))
  end

  private

  def unit_params
    permitted = params.require(:unit).permit(:code, :name, :kind, :status, :timezone, :parent_unit_id, settings: {})
    contact_center_access.units.find(permitted[:parent_unit_id]) if permitted[:parent_unit_id].present?
    settings = permitted[:settings].to_h
    validate_calendar_settings!(settings)
    validate_recording_policy_settings!(settings)
    settings = contact_center_access.units.find(params[:id]).settings.merge(settings) if action_name == 'update'
    JrcContactCenter::OrganizationalScope.new(account: Current.account, account_user: Current.account_user).authorize_links!(settings)
    permitted[:settings] = settings
    permitted
  end

  def serialize(unit)
    settings = unit.settings.except(JrcContactCenter::CalendarCatalogState::KEY, JrcContactCenter::RecordingPolicyDraft::KEY)
    unit.as_json(only: %i[id code name kind status timezone parent_unit_id settings created_at updated_at]).transform_keys(&:to_s)
        .merge('settings' => settings,
               'revision' => JrcContactCenter::ConfigurationRevision.token(unit))
  end

  def validate_recording_policy_settings!(settings)
    return unless settings.key?(JrcContactCenter::RecordingPolicyDraft::KEY)

    raise JrcContactCenter::OperationError, 'recording_policy_requires_typed_configuration'
  end

  def validate_calendar_settings!(settings)
    return unless settings.key?(JrcContactCenter::CalendarCatalogState::KEY)

    raise JrcContactCenter::OperationError, 'calendar_requires_typed_configuration'
  end
end
