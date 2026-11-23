require 'rails_helper'

RSpec.describe JrcContactCenter::ConfirmEndingReason do
  subject(:confirmation) { described_class.new(account: account, member: member) }

  include_context 'with a frozen ending reason catalogue'

  let(:attributes) { { reason_code: entry.fetch('code'), outcome_code: '', notes: 'SYNTHETIC private draft' } }
  let(:options) do
    { attributes: attributes, expected_revision: JrcContactCenter::QualificationDraftRevision.token(record), request_key: SecureRandom.uuid }
  end
  let(:ledger) { JrcContactCenter::EndingReasonConfirmation.find_by!(account: account, source_qualification_id: record.id) }

  it 'saves the complete explicit draft and an immutable classification without completing ACW or executing integrations' do
    confirmation.call(record, **options)
    value = JrcContactCenter::EndingConfirmationState.private_payload(record).fetch('ending_reason_confirmation')
    expect(record.reload.attributes.symbolize_keys).to include(attributes)
    expect(record.completed_at).to be_nil
    expected = { 'state' => 'confirmed', 'reason_label' => entry.fetch('name'), 'completes_acw' => false, 'executes_integrations' => false }
    expect(value).to include(expected)
    expect(ledger.actor_account_user_id).to eq(member.id)
    expect(ledger.payload.to_json).not_to include('SYNTHETIC private draft')
    expect(JrcContactCenter::AgentStateEvent.find_by!(external_event_id: "qualification:#{record.id}:pending").ended_at).to be_nil
  end

  it 'retains the frozen reason label even after the account publishes a new catalogue version' do
    record
    configure_ending_reasons!(entries: [entry.merge('name' => 'SYNTHETIC newer label')])
    confirmation.call(record, **options)
    expect(ledger.reason_label).to eq(entry.fetch('name'))
    expect(ledger.catalogue_id).to eq(session.reload.ending_reason_version_id)
  end

  it 'replays the same original input exactly once without demanding its now-stale preconfirmation revision' do
    input = options
    confirmation.call(record, **input)
    original = ledger.attributes.deep_dup
    expect { confirmation.call(record, **input) }.not_to change(JrcContactCenter::EndingReasonConfirmation, :count)
    expect(ledger.reload.attributes).to eq(original)
    expect(record.reload.completed_at).to be_nil
  end

  it 'rejects reuse of a request key with altered draft content instead of silently discarding the new answers' do
    input = options
    confirmation.call(record, **input)
    changed = input.merge(attributes: attributes.merge(notes: 'SYNTHETIC changed'))
    expect { confirmation.call(record, **changed) }.to raise_error(JrcContactCenter::OperationError, 'ending_confirmation_content_conflict')
    expect(record.reload.notes).to eq(attributes.fetch(:notes))
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account).count).to eq(1)
  end

  it 'rejects a second confirmation under a different request key' do
    confirmation.call(record, **options)
    expect { confirmation.call(record, **options, request_key: SecureRandom.uuid) }
      .to raise_error(JrcContactCenter::OperationError, 'ending_reason_already_confirmed')
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account).count).to eq(1)
  end

  it 'revalidates current eligibility even for an otherwise valid idempotent replay' do
    input = options
    confirmation.call(record, **input)
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    expect { confirmation.call(record, **input) }.to raise_error(Pundit::NotAuthorizedError)
    expect(record.reload.completed_at).to be_nil
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account).count).to eq(1)
  end

  it 'cannot confirm another administrator attendance through a supplied record identifier' do
    other = create(:user, :contact_center_eligible, account: account, role: :administrator)
    service = described_class.new(account: account, member: account.account_users.find_by!(user: other))
    expect { service.call(record, **options) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account)).to be_empty
  end

  it 'rolls back the draft if immutable receipt persistence fails' do
    previous = record.attributes.deep_dup
    allow(JrcContactCenter::EndingReasonConfirmation).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
    expect { confirmation.call(record, **options) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(record.reload.attributes).to eq(previous)
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account)).to be_empty
  end

  it 'rejects a stale revision without saving the draft or recording a confirmation' do
    expect { confirmation.call(record, **options, expected_revision: 'stale') }
      .to raise_error(JrcContactCenter::OperationError, 'stale_configuration_revision')
    expect(record.reload.reason_code).to be_nil
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account)).to be_empty
  end

  it 'rejects a reason outside the frozen registered catalogue without consuming the request key' do
    input = options.merge(attributes: attributes.merge(reason_code: 'unregistered'))
    expect { confirmation.call(record, **input) }.to raise_error(JrcContactCenter::OperationError, 'registered_ending_reason_required')
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account)).to be_empty
    expect(record.reload.notes).to be_nil
  end

  it 'freezes classification while permitting later notes and explicit native ACW completion' do
    confirmation.call(record, **options)
    before = ledger.attributes.deep_dup
    revision = JrcContactCenter::QualificationDraftRevision.token(record.reload)
    manager.save_draft!(record, { notes: 'SYNTHETIC reviewed notes' }, expected_revision: revision)
    expect(record.reload.notes).to eq('SYNTHETIC reviewed notes')
    expect(record.completed_at).to be_nil
    manager.complete!(record, reason_code: entry.fetch('code'), outcome_code: 'completed', notes: record.notes)
    expect(record.reload.completed_at).to be_present
    expect(ledger.reload.attributes).to eq(before)
  end

  it 'rejects reason replacement through either ordinary draft or native completion' do
    confirmation.call(record, **options)
    revision = JrcContactCenter::QualificationDraftRevision.token(record.reload)
    expect do
      manager.save_draft!(record, { reason_code: 'other' }, expected_revision: revision)
    end.to raise_error(JrcContactCenter::OperationError, 'ending_reason_already_confirmed')
    expect { manager.complete!(record, reason_code: 'other', outcome_code: 'completed') }
      .to raise_error(JrcContactCenter::OperationError, 'ending_reason_already_confirmed')
    expect(record.reload.reason_code).to eq(entry.fetch('code'))
    expect(record.completed_at).to be_nil
  end

  it 'rejects the previously valid preconfirmation revision without changing notes or the confirmed evidence' do
    input = options
    confirmation.call(record, **input)
    original = ledger.attributes.deep_dup
    expect do
      manager.save_draft!(record, { notes: 'SYNTHETIC stale replacement' }, expected_revision: input.fetch(:expected_revision))
    end.to raise_error(JrcContactCenter::OperationError, 'stale_configuration_revision')
    expect(record.reload.notes).to eq(attributes.fetch(:notes))
    expect(ledger.reload.attributes).to eq(original)
    expect(record.completed_at).to be_nil
  end
end
