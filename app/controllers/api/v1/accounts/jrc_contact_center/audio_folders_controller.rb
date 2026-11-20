# frozen_string_literal: true

# Institutional folders use current native unit coverage, never the call-recording permission.
class Api::V1::Accounts::JrcContactCenter::AudioFoldersController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action -> { response.headers['Cache-Control'] = 'no-store' }
  before_action -> { authorize_contact_center!(:configure?) }

  def index
    params[:page] = 1 if params[:page].blank?
    relation = scoped_folders.where(unit_id: permitted_unit(params.require(:unit_id)).id)
    relation = within_parent(relation)
    render json: list_payload(search_records(relation, fields: ['name']).order(:name, :id)) { |folder| present(folder) }
  end

  def show
    render json: base_payload.merge(item: present(scoped_folders.find(identifier!(params[:id]))))
  end

  def create
    with_current_folder_authority do
      values = folder_attributes(creating: true)
      unit = permitted_unit(values.delete('unit_id'))
      folder = JrcContactCenter::AudioFolder.new(values.merge(account: Current.account, unit: unit))
      check_parent!(folder)
      folder.save!
      render json: base_payload.merge(item: present(folder)), status: :created
    end
  end

  def update
    with_current_folder_authority do
      folder = scoped_folders.find(identifier!(params[:id]))
      JrcContactCenter::ConfigurationRevision.check!(folder, params[:expected_revision])
      folder.assign_attributes(folder_attributes(creating: false))
      check_parent!(folder)
      folder.save!
      render json: base_payload.merge(item: present(folder))
    end
  end

  private

  def within_parent(relation)
    return relation unless params.key?(:parent_id)

    selected = params[:parent_id]
    parent = selected.nil? || selected == '' ? nil : relation.find(identifier!(selected))
    relation.where(parent_id: parent&.id)
  end

  def with_current_folder_authority
    JrcContactCenter::AuthorityTransaction.call(account: Current.account, member: Current.account_user) do
      Current.user.reload
      raise Pundit::NotAuthorizedError unless Current.user.active_for_authentication?

      @contact_center_access = JrcContactCenter::AccessScope.new(user_context: pundit_user)
      raise Pundit::NotAuthorizedError unless @contact_center_access.policy.configure?

      yield
    end
  end

  def scoped_folders
    JrcContactCenter::AudioFolder.where(account: Current.account, unit_id: contact_center_access.units.select(:id)).includes(:parent)
  end

  def permitted_unit(id)
    contact_center_access.units.find(identifier!(id))
  end

  def check_parent!(folder)
    return if folder.parent_id.blank?

    scoped_folders.where(unit_id: folder.unit_id).find(folder.parent_id)
  end

  def folder_attributes(creating:)
    values = params.require(:folder)
    keys = creating ? %w[unit_id name description parent_id] : %w[name description parent_id]
    valid = values.respond_to?(:permit) && (values.keys - keys).empty?
    raise JrcContactCenter::OperationError, 'invalid_audio_folder' unless valid

    validate_folder_values!(values.to_unsafe_h, creating: creating)
    values = values.permit(*keys).to_h
    values['parent_id'] = nil if values['parent_id'] == ''
    values
  end

  def validate_folder_values!(values, creating:)
    identifier!(values['unit_id']) if creating
    identifier!(values['parent_id']) unless [nil, ''].include?(values['parent_id'])
    valid = values.slice('name', 'description').all? do |key, value|
      value.is_a?(String) || (key == 'description' && value.nil?)
    end
    raise JrcContactCenter::OperationError, 'invalid_audio_folder' unless valid
  end

  def identifier!(value)
    text = value.to_s
    valid = (value.is_a?(String) || value.is_a?(Integer)) && text.match?(/\A[1-9][0-9]{0,18}\z/) && text.to_i <= 9_223_372_036_854_775_807
    raise JrcContactCenter::OperationError, 'invalid_audio_folder' unless valid

    text
  end

  def present(folder)
    folder.as_json(only: %i[id unit_id parent_id name description created_at updated_at])
          .merge('id' => folder.id.to_s, 'unit_id' => folder.unit_id.to_s,
                 'parent_id' => folder.parent_id&.to_s, 'parent_name' => folder.parent&.name,
                 'revision' => JrcContactCenter::ConfigurationRevision.token(folder))
  end
end
