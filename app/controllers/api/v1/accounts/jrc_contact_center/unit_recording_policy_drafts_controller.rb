# frozen_string_literal: true

# One local draft on the existing authorized unit; never provider state.
class Api::V1::Accounts::JrcContactCenter::UnitRecordingPolicyDraftsController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action :private_response
  rescue_from ArgumentError, ActionController::ParameterMissing, JSON::ParserError, with: :invalid_request

  def show
    authorize_contact_center!(:configure?)
    unit = contact_center_access.units.find(policy_unit_id)
    render json: presentation(unit)
  end

  def update
    authorize_contact_center!(:configure?)
    input = policy_document
    unit = configuration_write.update!(contact_center_access.units, policy_unit_id, expected_revision: input['expected_revision']) do
      current = contact_center_access.units.find(policy_unit_id)
      definition = JrcContactCenter::RecordingPolicyDraft.build(unit: current, values: input.fetch('recording_policy_draft'))
      JrcContactCenter::RecordingPolicyDraft.authorize_queues!(unit: current, definition: definition, scope: contact_center_access.queues)
      { settings: current.settings.merge(JrcContactCenter::RecordingPolicyDraft::KEY => definition) }
    end
    render json: presentation(unit)
  end

  private

  def policy_unit_id
    JrcServiceDesk::Input.id(params[:id])
  end

  def presentation(unit)
    definition = JrcContactCenter::RecordingPolicyDraft.stored(unit)
    if definition
      JrcContactCenter::RecordingPolicyDraft.authorize_queues!(unit: unit, definition: definition, scope: contact_center_access.queues)
    end
    base_payload.merge(unit_id: unit.id.to_s, unit_name: unit.name, time_zone: unit.timezone,
                       revision: JrcContactCenter::ConfigurationRevision.token(unit), draft: definition,
                       applied: false, provider_state: 'not_verified')
  end

  def policy_document
    raise ArgumentError unless request.media_type == 'application/json' && request.raw_post.bytesize.between?(1, 16_384)

    values = ActiveSupport::JSON.decode(request.raw_post)
    raise ArgumentError unless values.is_a?(Hash) && (values.keys - %w[recording_policy_draft expected_revision]).empty?
    raise ArgumentError unless values.key?('recording_policy_draft')

    values
  end

  def private_response
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end

  def invalid_request
    render json: base_payload.merge(error: JrcContactCenter::RecordingPolicyDraft::ERROR), status: :unprocessable_entity
  end
end
