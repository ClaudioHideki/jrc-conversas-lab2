# Called only by SyntheticPauseSeed after its exclusive runner, PostgreSQL and Redis checks.
class JrcContactCenter::SyntheticEndingConfirmationSeed
  def self.call(account:, admin:, operator:, queue:)
    form = JrcContactCenter::SyntheticOperationalFormSeed.new(
      account: account, admin: admin, queue: queue, reason_code: 'synthetic_registered', rule_id: 'synthetic-confirmed-ending'
    ).call
    ending = JrcContactCenter::SyntheticEndingReasonSeed.new(account: account, admin: admin, operator: operator, queue: queue).call
    record = JrcContactCenter::Qualification.find_by!(account: account, account_user: operator, call_session_id: ending.fetch(:call_session_id))
    context = JrcContactCenter::QualificationForms.new(record).private_payload(reason: ending.fetch(:ending_reason_code))
    selected = context.dig('acw_form_context', 'selected', 'form_id')
    raise 'Synthetic confirmed ending must have the original native form' unless selected == form[:form_id]

    form.merge(ending)
  end
end
