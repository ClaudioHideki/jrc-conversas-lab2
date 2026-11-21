# frozen_string_literal: true

# Delegates authority to the current native policy and corporate unit scope; file identifiers grant nothing.
class JrcContactCenter::AudioLibraryAccess
  attr_reader :account, :actor, :member, :scope

  def initialize(context:)
    @context = context
    @account = context.fetch(:account)
    @actor = context.fetch(:user)
    @member = context.fetch(:account_user)
    refresh!
  end

  def refresh!
    @member.reload
    @actor.reload
    @account.reload
    raise Pundit::NotAuthorizedError unless @actor.active_for_authentication?

    @scope = JrcContactCenter::AccessScope.new(user_context: @context)
    raise Pundit::NotAuthorizedError unless @scope.policy.configure?

    self
  end

  def transaction
    JrcContactCenter::AuthorityTransaction.call(account: @account, member: @member) do
      refresh!
      yield
    end
  end

  def units
    @scope.units
  end

  def unit(id)
    units.find(identifier!(id))
  end

  def assets
    JrcContactCenter::AudioAsset.where(account: @account, unit_id: units.select(:id))
                                .includes(:folder, latest_version: %i[created_by latest_inspection])
  end

  def asset(id)
    assets.find(identifier!(id))
  end

  def folder(id, unit:)
    return if id.nil? || id == ''

    current_unit = self.unit(unit.id)
    JrcContactCenter::AudioFolder.where(account: @account, unit: current_unit).find(identifier!(id))
  end

  def versions(asset)
    current = self.asset(asset.id)
    JrcContactCenter::AudioVersion.where(account: @account, unit_id: current.unit_id, audio_asset: current)
  end

  def latest(asset)
    versions(asset).order(number: :desc).first
  end

  def inspections(version)
    current = versions(asset(version.audio_asset_id)).find(version.id)
    JrcContactCenter::AudioInspection.where(account: @account, unit_id: current.unit_id, audio_version: current)
  end

  # Bounded metadata projection for local draft references. No blobs or bytes are read.
  def reference_versions(unit_id:, asset_ids:, version_ids:)
    current_unit = unit(unit_id)
    raise ActiveRecord::RecordNotFound unless current_unit.status == 'active'

    permitted = assets.where(unit_id: current_unit.id, id: reference_ids!(asset_ids)).select(:id)
    JrcContactCenter::AudioVersion.where(account: @account, unit: current_unit, audio_asset_id: permitted, id: reference_ids!(version_ids))
                                 .includes(:latest_inspection)
  end

  def identifier!(value)
    text = value.to_s
    valid = (value.is_a?(String) || value.is_a?(Integer)) && text.match?(/\A[1-9][0-9]{0,18}\z/) && text.to_i <= 9_223_372_036_854_775_807
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio' unless valid

    text
  end

  private

  def reference_ids!(values)
    valid = values.is_a?(Array) && values.length.between?(1, 128)
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio' unless valid

    values.map { |value| identifier!(value) }.uniq
  end
end
