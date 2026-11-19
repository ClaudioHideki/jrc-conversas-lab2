require 'rails_helper'

RSpec.describe JrcContactCenter::QualificationForm do
  include_context 'with an owned immutable operational ACW form'

  it 'rejects direct rewriting of the frozen definition references through PostgreSQL' do
    state = service.state
    original = state.snapshot.deep_dup
    expect do
      described_class.transaction(requires_new: true) do
        state.update_columns(snapshot: original.merge('bindings' => []))
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /jrc_cc_qualification_form_snapshot_immutable/)
    expect(state.reload.snapshot).to eq(original)
  end

  it 'refuses direct cross-account reassignment even when the supplied account exists' do
    state = service.state
    other = create(:account)
    expect do
      described_class.transaction(requires_new: true) { state.update_columns(account_id: other.id) }
    end.to raise_error(ActiveRecord::StatementInvalid, /jrc_cc_qualification_form_identity/)
    expect(state.reload.account_id).to eq(account.id)
  end

  it 'keeps historical scope links immutable rather than allowing a new unit to grant read access' do
    state = service.state
    unit = JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC', name: 'SYNTHETIC scope tamper', kind: 'sac')
    expect do
      described_class.transaction(requires_new: true) { state.update_columns(unit_id: unit.id) }
    end.to raise_error(ActiveRecord::StatementInvalid, /jrc_cc_qualification_form_snapshot_immutable/)
    expect(state.reload.unit_id).to be_nil
  end

  it 'cannot discard an individual private response while its native parent and account remain' do
    state = service.state
    expect do
      described_class.transaction(requires_new: true) { state.delete }
    end.to raise_error(ActiveRecord::StatementInvalid, /jrc_cc_qualification_form_history_immutable/)
    expect(described_class.exists?(state.id)).to be(true)
    expect(record.reload.completed_at).to be_nil
  end

  it 'seals persisted responses after actual native completion even for direct SQL updates' do
    manager.complete!(record, completion)
    state = service.state
    expect do
      described_class.transaction(requires_new: true) { state.update_columns(answers: {}) }
    end.to raise_error(ActiveRecord::StatementInvalid, /jrc_cc_qualification_form_answers_sealed/)
    expect(state.reload.answers).to eq(answers)
    expect(record.reload.completed_at).to be_present
  end

  it 'does not permit clearing native completion to reopen and rewrite a sealed private response' do
    manager.complete!(record, completion)
    timestamp = record.reload.completed_at
    expect do
      JrcContactCenter::Qualification.transaction(requires_new: true) { record.update_columns(completed_at: nil) }
    end.to raise_error(ActiveRecord::StatementInvalid, /jrc_cc_qualification_form_completion_sealed/)
    expect(record.reload.completed_at).to eq(timestamp)
    expect(service.state.answers).to eq(answers)
  end

  it 'does not permit rewriting the native classification or source after form completion' do
    manager.complete!(record, completion)
    expect do
      JrcContactCenter::Qualification.transaction(requires_new: true) { record.update_columns(reason_code: 'resolved') }
    end.to raise_error(ActiveRecord::StatementInvalid, /jrc_cc_qualification_form_completion_sealed/)
    expect(record.reload.reason_code).to eq('order')
  end

  it 'refuses a fabricated origin even when the native qualification identity is otherwise correct' do
    state = service.state
    snapshot = state.snapshot.deep_dup
    snapshot['origin']['revision'] = '0' * 64
    values = state.attributes.except('id').merge('snapshot' => snapshot)
    expect do
      described_class.transaction(requires_new: true) { described_class.insert_all!([values]) }
    end.to raise_error(ActiveRecord::StatementInvalid, /jrc_cc_qualification_form_origin/)
    expect(service.state.snapshot).to eq(state.snapshot)
  end

  it 'does not expose schema or private response content through model inspection or the shared native payload' do
    manager.complete!(record, completion)
    expect(service.state.inspect).not_to include('SYNTHETIC private response', 'SYNTHETIC feedback')
    expect(record.operational_payload.to_json).not_to include('SYNTHETIC private response', 'acw_form_context')
  end
  it 'rejects an existing foreign-account form version nested in an otherwise valid native origin' do
    state = service.state
    foreign = create(:account)
    foreign_user = create(:user, :contact_center_eligible, account: foreign, role: :administrator)
    foreign_member = foreign.account_users.find_by!(user: foreign_user)
    template = JrcContactCenter::AcwFormTemplate.create!(account: foreign)
    version = JrcContactCenter::AcwFormVersion.create!(
      account: foreign, acw_form_template: template, revision: 1, name: 'SYNTHETIC foreign version', description: '', status: 'active',
      definition: definition, actor_account_user_id: foreign_member.id, actor_user_id: foreign_user.id, request_id: SecureRandom.uuid
    )
    snapshot = state.snapshot.deep_dup
    snapshot['bindings'].first.merge!('form_id' => template.id.to_s, 'integrity_sha256' => version.integrity_sha256)
    expect do
      described_class.transaction(requires_new: true) { described_class.insert_all!([state.attributes.except('id').merge('snapshot' => snapshot)]) }
    end.to raise_error(ActiveRecord::StatementInvalid, /jrc_cc_qualification_form_version/)
    expect(service.state.snapshot).to eq(state.snapshot)
  end

  it 'preserves the native account retirement block instead of deleting attendance evidence to bypass it' do
    state = service.state
    expect do
      Account.transaction(requires_new: true) { account.destroy! }
    end.to raise_error(ActiveRecord::InvalidForeignKey, /jrc_contact_center_/)
    expect(described_class.exists?(state.id)).to be(true)
    expect(JrcContactCenter::Qualification.exists?(record.id)).to be(true)
    expect(Account.exists?(account.id)).to be(true)
  end
end
