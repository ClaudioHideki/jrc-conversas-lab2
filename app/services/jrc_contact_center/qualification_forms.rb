# frozen_string_literal: true

require 'openssl'

# Callers retain current own-attendance authorization and the native Account/qualification locks.
class JrcContactCenter::QualificationForms
  KEY = :acw_form_answers

  def initialize(record)
    @record = record
  end

  def state
    JrcContactCenter::QualificationForm.find_by(account_id: @record.account_id, qualification_id: @record.id)
  end

  def private_payload(reason: @record.reason_code)
    row = state
    return {} unless row

    authorize_source!(row)
    { 'acw_form_context' => { 'selected' => selected_form(row, reason), 'answers' => row.answers.deep_dup,
                              'reason_codes' => row.snapshot.fetch('reason_codes').deep_dup } }
  end

  def revision_component
    row = state
    return unless row

    authorize_source!(row)
    snapshot = JrcContactCenter::QualificationFormSnapshot.new(@record).call(row)
    normalized = JrcServiceDesk::CanonicalJson.normalize([snapshot, row.answers])
    key = Rails.application.key_generator.generate_key('jrc_cc_qualification_forms_revision_v1')
    ['qualification_forms_v1', row.id, OpenSSL::HMAC.hexdigest('SHA256', key, JSON.generate(normalized))]
  end

  def validate_completion!
    row = state
    return unless row

    authorize_source!(row)
    snapshot = JrcContactCenter::QualificationFormSnapshot.new(@record).call(row)
    validator = JrcContactCenter::QualificationFormValues.new(account: @record.account, snapshot: snapshot)
    answers = validator.merge(row.answers, :unchanged)
    validator.complete!(binding_for(snapshot, @record.reason_code), answers)
  end

  def save!(attributes, complete:)
    row = state
    input = attributes.fetch(KEY, :unchanged)
    unless row
      raise JrcContactCenter::AcwFormAnswers::Invalid unless input == :unchanged || input == {}

      return
    end

    save_state!(row, attributes, input, complete)
  end

  private

  def save_state!(row, attributes, input, complete)
    authorize_source!(row)
    snapshot = JrcContactCenter::QualificationFormSnapshot.new(@record).call(row)
    validator = JrcContactCenter::QualificationFormValues.new(account: @record.account, snapshot: snapshot)
    answers = validator.merge(row.answers, input)
    selected = binding_for(snapshot, attributes.fetch(:reason_code, @record.reason_code))
    validator.complete!(selected, answers) if complete
    row.update!(answers: answers) unless row.answers == answers
  end

  # Same corporate predicates as native records; immutable original links cannot become grants after a transfer.
  # Write callers already hold the native Account/qualification locks; do not acquire a late AccountMutex here.
  def authorize_source!(row)
    AccountUser.uncached do
      account = Account.find(@record.account_id)
      member = account.account_users.find(@record.account_user_id)
      context = { account: account, account_user: member, user: member.user }
      allowed = member.user.reload.active_for_authentication? && JrcContactCenter::ModulePolicy.new(context, :contact_center).operate?
      raise Pundit::NotAuthorizedError unless allowed

      JrcContactCenter::QualificationFormVisibility.authorize!(row, account: account, member: member)
    end
  end

  def binding_for(snapshot, reason)
    return if reason.blank?
    registered = JrcContactCenter::EndingReasonPolicy.new(@record).registered?(reason)
    raise JrcContactCenter::OperationError, 'invalid_qualification_form_reason' unless snapshot.fetch('reason_codes').include?(reason) || registered

    origin = snapshot.fetch('origin')
    rule = JrcContactCenter::AcwRulePrecedence.new(rules: origin.fetch('rules')).call(
      reason_code: reason, queue_id: origin.fetch('queue_id'), team_ids: origin.fetch('team_ids')
    )
    snapshot.fetch('bindings').find { |pin| pin.fetch('rule_id') == rule.fetch('id') } if rule
  end

  def selected_form(row, reason)
    snapshot = JrcContactCenter::QualificationFormSnapshot.new(@record).call(row)
    binding = binding_for(snapshot, reason)
    return unless binding

    JrcContactCenter::AcwFormBindings.new(account: @record.account).resolve!(binding).merge('rule_id' => binding.fetch('rule_id'))
  end
end
