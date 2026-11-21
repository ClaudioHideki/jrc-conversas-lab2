# frozen_string_literal: true

class JrcContactCenter::TeamSupervisions
  def initialize(context:)
    @account = context.fetch(:account)
    @actor = context.fetch(:account_user)
    @authority = JrcContactCenter::AccessAuthorization.new(context: context)
  end

  def team(id)
    authorize!
    @account.teams.find(id)
  end

  def authorize!
    @account.reload
    @actor&.reload
    @authority.authorize!
  end

  def update!(id:, attributes:, expected:)
    input = JrcContactCenter::TeamSupervisionInput.new(attributes)
    JrcContactCenter::AuthorityTransaction.call(account: @account, member: @actor) do
      record = team(id)
      JrcContactCenter::ConfigurationRevision.check_token!(revision(record), expected)
      validate_selection!(record, input)
      reconcile!(record, input.assignments)
      present(record)
    end
  end

  def present(record)
    authorize!
    raise ActiveRecord::RecordNotFound unless record.account_id == @account.id

    eligibility = JrcContactCenter::TeamSupervisorEligibility.new(account: @account, team: record)
    rows = assignments(record).includes(account_user: :user).map do |row|
      eligibility.present(row.account_user).merge(id: row.id.to_s, kind: row.kind)
    end
    selection_fields(rows).merge(id: record.id.to_s, name: record.name, revision: revision(record),
                                 active: JrcContactCenter::TeamState.source_active?(account: @account, team_id: record.id))
  end

  def candidate(record, member)
    authorize!
    JrcContactCenter::TeamSupervisorEligibility.new(account: @account, team: record).present(member)
  end

  def append_summaries(payload)
    authorize!
    rows = payload.fetch(:items)
    grouped = JrcContactCenter::TeamSupervision.where(account: @account, team_id: rows.pluck(:id))
                                               .includes(account_user: :user).group_by(&:team_id)
    rows.each do |row|
      row.merge!(summary_fields(row.fetch(:id), grouped))
    end
    payload
  end

  private

  def summary_fields(id, grouped)
    selected = grouped.fetch(id, [])
    primary = selected.find { |person| person.kind == 'primary' }
    { team_identity: id.to_s, primary_supervisor: primary&.account_user&.user&.name,
      additional_supervisor_count: selected.count { |person| person.kind == 'additional' } }
  end

  def selection_fields(rows)
    primary = rows.find { |row| row[:kind] == 'primary' }
    additional = rows.select { |row| row[:kind] == 'additional' }
    { supervisors: rows, primary_account_user_id: primary&.fetch(:account_user_id),
      additional_account_user_ids: additional.pluck(:account_user_id),
      primary_supervisor: primary&.fetch(:name), additional_supervisors: additional.pluck(:name) }
  end

  def assignments(record)
    JrcContactCenter::TeamSupervision.where(account: @account, team: record).order(:account_user_id, :id)
  end

  def revision(record)
    grant = @authority.grant_for(record)
    scopes = JrcCrm::TeamScope.where(account: @account, team: record).order(:id).map(&:attributes)
    selection = assignments(record).map(&:attributes)
    Digest::SHA256.hexdigest([@authority.revision(record, grant), scopes, selection].to_json)
  end

  def validate_selection!(record, input)
    ids = input.assignments.pluck(:account_user_id)
    members = @account.account_users.where(id: ids).includes(:user, :custom_role).to_a
    raise ActiveRecord::RecordNotFound unless members.map(&:id).sort == ids.sort

    eligibility = JrcContactCenter::TeamSupervisorEligibility.new(account: @account, team: record)
    invalid = members.any? { |member| eligibility.reason(member) }
    raise JrcContactCenter::OperationError, 'ineligible_team_supervisor' if invalid
  end

  def reconcile!(record, desired)
    selected = desired.index_by { |row| row.fetch(:account_user_id) }
    remove_or_demote!(record, selected)
    persist_selection!(record, desired)
  end

  def remove_or_demote!(record, selected)
    assignments(record).each do |row|
      attributes = selected[row.account_user_id]
      row.destroy! unless attributes
      row.update!(kind: 'additional') if attributes && row.kind == 'primary' && attributes.fetch(:kind) != 'primary'
    end
  end

  def persist_selection!(record, desired)
    desired.each do |attributes|
      identity = { account: @account, team: record, account_user_id: attributes.fetch(:account_user_id) }
      row = JrcContactCenter::TeamSupervision.find_or_initialize_by(identity)
      row.kind = attributes.fetch(:kind)
      row.save! if row.new_record? || row.changed?
    end
  end
end
