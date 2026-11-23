require 'rails_helper'

# Prepared native PostgreSQL tests. No result is claimed until the complete owned
# migration, receipt and test increment has actually run in its disposable CI.
RSpec.describe JrcContactCenter::EndingActionOrigin do
  include_context 'with native ending execution original evidence'

  it 'captures the actual pending event actor, answered leg and immutable version without arming an effect' do
    expect(origin.actor_account_user_id).to eq(member.id)
    expect(origin.actor_user_id).to eq(actor.id)
    expect(origin.call_session_id).to eq(source_call.id)
    expect(origin.call_leg_id).to eq(source_leg.id)
    expect(origin.queue_scope_version_id).to eq(scope.id)
    expect(origin.version.definition.fetch('entries').sole).not_to have_key('execution_token')
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not create original evidence merely by configuring an explicit automatic mode' do
    expect(described_class.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingActionCompletion.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'retains one origin when native terminal repair and tabulation are replayed' do
    first = origin.attributes.deep_dup
    2.times { JrcContactCenter::QualificationManager.ensure_voice!(source_call.reload) }
    expect(described_class.where(account: account).count).to eq(1)
    expect(origin.reload.attributes).to eq(first)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'keeps early reason confirmation distinct from a real ACW completion and any execution' do
    origin
    JrcContactCenter::ConfirmEndingReason.new(account: account, member: member).call(
      qualification, attributes: { reason_code: 'SYNTHETIC_ORIGIN_REASON' },
      expected_revision: JrcContactCenter::QualificationDraftRevision.token(qualification), request_key: SecureRandom.uuid
    )
    expect(qualification.reload.completed_at).to be_nil
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account).count).to eq(1)
    expect(JrcContactCenter::EndingActionCompletion.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'captures an actual native completed ACW without demanding an additional early reason confirmation' do
    original = origin
    complete_origin_qualification
    receipt = JrcContactCenter::EndingActionCompletion.find_by!(account: account, origin: original)
    expect(receipt.source_qualification_id).to eq(qualification.id)
    expect(receipt.reason_code).to eq('SYNTHETIC_ORIGIN_REASON')
    expect(receipt.outcome_code).to eq('completed')
    expect(receipt.completed_at).to eq(qualification.reload.completed_at)
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'retains one immutable completion when the same native completion is submitted twice' do
    original = origin
    complete_origin_qualification
    first = JrcContactCenter::EndingActionCompletion.find_by!(account: account, origin: original).attributes.deep_dup
    complete_origin_qualification
    expect(JrcContactCenter::EndingActionCompletion.where(account: account).count).to eq(1)
    expect(JrcContactCenter::EndingActionCompletion.find_by!(account: account, origin: original).attributes).to eq(first)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rejects direct SQL origin edits rather than relying only on model callbacks' do
    first = origin.attributes.deep_dup
    expect { guarded_origin_sql("UPDATE #{described_class.table_name} SET actor_user_id=0 WHERE id=#{origin.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /Ending action original evidence is immutable/)
    expect(origin.reload.attributes).to eq(first)
  end

  it 'rejects direct SQL origin deletion while the account remains live' do
    identifier = origin.id
    expect { guarded_origin_sql("DELETE FROM #{described_class.table_name} WHERE id=#{identifier}") }
      .to raise_error(ActiveRecord::StatementInvalid, /Ending action original evidence is immutable/)
    expect(described_class.exists?(identifier)).to be(true)
  end

  it 'rejects another accounts event instead of treating a supplied account or event id as source authority' do
    original = origin
    other = create(:account)
    expect do
      guarded_origin_sql("INSERT INTO #{described_class.table_name}(account_id,origin_event_id) VALUES(#{other.id},#{original.origin_event_id})")
    end.to raise_error(ActiveRecord::StatementInvalid, /Ending action native origin event unavailable/)
    expect(described_class.where(account: other)).to be_empty
    expect(origin.reload.actor_user_id).to eq(actor.id)
  end

  it 'preserves source evidence when native qualification cleanup nullifies only its live relation' do
    first = origin.attributes.deep_dup
    guarded_origin_sql("DELETE FROM jrc_contact_center_qualifications WHERE id=#{qualification.id}")
    expect(origin.reload.qualification_id).to be_nil
    expect(origin.source_qualification_id).to eq(qualification.id)
    expect(origin.attributes.except('qualification_id')).to eq(first.except('qualification_id'))
  end

  it 'does not permit manually severing a still-live qualification relation' do
    original = origin
    expect { guarded_origin_sql("UPDATE #{described_class.table_name} SET qualification_id=NULL WHERE id=#{original.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /Ending action original evidence is immutable/)
    expect(origin.reload.qualification_id).to eq(qualification.id)
  end

  it 'rejects retargeting the original leg scope after capture without altering its actual operational identity' do
    original = origin
    expect do
      guarded_origin_sql("UPDATE jrc_contact_center_call_legs SET ending_action_scope_version_id=NULL WHERE id=#{source_leg.id}")
    end.to raise_error(ActiveRecord::StatementInvalid, /Call leg ending action origin is immutable/)
    expect(source_leg.reload.ending_action_scope_version_id).to eq(original.queue_scope_version_id)
    expect(origin.reload.call_leg_id).to eq(source_leg.id)
  end

  context 'when no queue was known on original leg creation' do
    let(:source_leg) do
      JrcContactCenter::CallLeg.create!(account: account, call_session: source_call, account_user: member, queue: nil,
                                        direction: 'inbound', status: 'connected', started_at: source_call.started_at,
                                        answered_at: source_call.answered_at)
    end

    it 'preserves native ACW but never reconstructs automation evidence from a later queue correction' do
      qualification
      expect(source_leg.reload.ending_action_scope_version_id).to be_nil
      source_leg.update!(queue: queue)
      JrcContactCenter::QualificationManager.ensure_voice!(source_call.reload)
      expect(source_leg.reload.ending_action_scope_version_id).to be_nil
      expect(described_class.where(account: account)).to be_empty
      expect(qualification.reload.completed_at).to be_nil
      expect(JrcProjects::Task.where(account: account)).to be_empty
    end
  end

  context 'when a call was observed after the reason catalogue but before the automation configuration' do
    let(:source_call) do
      reason = JrcContactCenter::EndingReasonVersion.where(account: account).order(:revision).last
      automation = JrcContactCenter::EndingActionVersion.where(account: account).order(:revision).last
      time = reason.created_at + ((automation.created_at - reason.created_at) / 2)
      new_origin_source_call(started_at: time)
    end

    it 'does not apply the later automation to the earlier first-observed call' do
      qualification
      expect(source_call.reload.ending_reason_version_id).not_to be_nil
      expect(source_leg.reload.ending_action_scope_version_id).to be_nil
      expect(described_class.where(account: account)).to be_empty
      expect(JrcProjects::Task.where(account: account)).to be_empty
    end
  end
end
