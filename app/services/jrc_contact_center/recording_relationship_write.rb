# frozen_string_literal: true

require 'digest'

# Explicit current-user work, through the native Relationship workflow.
# Account and assignment locks protect one native action/activity per request.
class JrcContactCenter::RecordingRelationshipWrite
  def initialize(account:, member:)
    @account = account
    @member = member
    @scope = JrcContactCenter::RecordingRelationshipScope.new(account: account, member: member)
  end

  def call(recording_id, values)
    input = normalize(values)
    candidate = @scope.with_origin(recording_id) do |_record, call, contact, context|
      @scope.assignments(context, call, contact).find(input.fetch(:assignment_id))
    end
    # Match native portfolio lock ordering. Release the initial source mutex
    # before waiting, then reauthorize both domains inside create_after_wait.
    candidate.with_lock { create_after_wait(recording_id, input, candidate.id) }
  end

  private

  def create_after_wait(recording_id, input, assignment_id)
    @scope.with_origin(recording_id, lock: true) do |record, call, contact, context|
      @scope.assignments(context, call, contact).find(assignment_id)
      assignment = context.assignment(assignment_id, write: true)
      origin = @scope.origin(record, call, contact, context)
      verify_origin_revision!(origin, input.fetch(:origin_revision))
      key = "control-desk-recording:#{@member.id}:#{input.fetch(:request_id)}"
      fingerprint = Digest::SHA256.hexdigest([assignment.id, origin, input.except(:request_id)].to_json)
      activity, replayed = persist(context, assignment, input, origin, key, fingerprint)
      context.audit!(activity, after: origin, action: replayed ? 'control_desk_activity_reused' : 'control_desk_activity_created')
      { recording_id: record.id.to_s, call_session_id: call.id.to_s, activity_id: activity.id.to_s,
        assignment_id: assignment.id.to_s, replayed: replayed, target: readable_target(activity) }
    end
  end

  def normalize(values)
    valid = values.is_a?(Hash) && values.keys.sort == %w[assignment_id due_at origin_revision request_id title]
    raise ArgumentError, 'Solicitação de registro inválida.' unless valid

    key = values.fetch('request_id')
    valid_key = key.is_a?(String) && key.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/)
    raise ArgumentError, 'Identificação da solicitação inválida.' unless valid_key

    revision = values.fetch('origin_revision')
    raise ArgumentError, 'Revisão da origem inválida.' unless revision.is_a?(String) && revision.match?(/\A[0-9a-f]{64}\z/)

    title = values.fetch('title')
    raise ArgumentError, 'Informe um título de até 250 caracteres.' unless title.is_a?(String) && title.strip.length.between?(1, 250)

    { assignment_id: JrcServiceDesk::Input.id(values['assignment_id']), request_id: key, origin_revision: revision, title: title.strip,
      due_at: deadline(values.fetch('due_at')) }
  end

  def deadline(value)
    pattern = /\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,6})?(?:Z|[+-][0-9]{2}:[0-9]{2})\z/
    raise ArgumentError, 'Informe data e hora explícitas com fuso horário.' unless value.is_a?(String) && value.match?(pattern)

    Date.iso8601(value.first(10))
    Time.iso8601(value).utc.iso8601(6)
  end

  def verify_origin_revision!(origin, expected)
    return if Digest::SHA256.hexdigest(origin.to_json) == expected

    raise JrcContactCenter::OperationError.new('recording_relationship_source_changed', status: :conflict)
  end

  def persist(context, assignment, input, origin, key, fingerprint)
    # The account-only lookup can reject an actor's reused key in another
    # portfolio; it never grants access or discloses that portfolio's content.
    existing = JrcRelationship::Action.where(account: @account, source_key: "activity:#{key}").first
    return [replay(context, assignment, existing, fingerprint), true] if existing

    activity = JrcRelationship::Workflow.new(context).activity!(assignment: assignment, title: input.fetch(:title),
                                                               due_at: input.fetch(:due_at), request_id: key, kind: 'call')
    raise ArgumentError, 'O fluxo nativo não gerou a atividade.' unless activity

    action = assignment.actions.find_by!(activity: activity)
    evidence = { 'control_desk_recording_origin' => origin, 'control_desk_request_sha256' => fingerprint }
    link_origin!(action, activity, evidence, origin)
    [activity, false]
  end

  def link_origin!(action, activity, evidence, origin)
    business = @account.jrc_crm_business_units.where(active: true).find(origin.fetch('business_unit_id'))
    activity.update!(business_unit: business, metadata: activity.metadata.merge(evidence))
    sources = action.metadata.fetch('_source_ids', {})
    sources = sources.merge('activities' => (sources.fetch('activities', []) + [activity.id]).uniq)
    # Reuse native SnapshotAccess, so a global portfolio cannot disclose this
    # unit's activity to a reader outside its current native CRM scope.
    action.update!(metadata: action.metadata.merge(evidence).merge('_source_ids' => sources))
  end

  def replay(context, assignment, action, fingerprint)
    authorized = context.records(JrcRelationship::Action).find(action.id)
    valid = authorized.assignment_id == assignment.id && authorized.metadata['control_desk_request_sha256'] == fingerprint
    raise JrcContactCenter::OperationError.new('recording_relationship_request_conflict', status: :conflict) unless valid

    authorized.activity || raise(ArgumentError, 'A atividade nativa anterior está indisponível.')
  end

  def readable_target(activity)
    JrcDomainCommands::ResourceScope.new(account: @account, user: @member.user).authorize!(activity)
    { kind: 'crm_activity', id: activity.id.to_s }
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    nil
  end
end
