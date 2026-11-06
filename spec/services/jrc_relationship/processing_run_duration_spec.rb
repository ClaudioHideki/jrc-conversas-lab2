require 'rails_helper'

RSpec.describe JrcRelationship::ProcessingRun do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:start) { Time.zone.parse('2026-11-06 12:00:00') }
  let(:run) do
    described_class.create!(account: account, viewer: actor, access_signature: context.access_signature,
                            requested_ids: [assignment.id], outcomes: { assignment.id.to_s => 'processed' },
                            state: 'completed', started_at: start, finished_at: start + 1.234.seconds)
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'derives milliseconds from persisted timestamps without changing the execution or turning filtered counts into totals' do
    hidden = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    run.update!(requested_ids: [assignment.id, hidden.id], outcomes: { assignment.id.to_s => 'processed', hidden.id.to_s => 'processing_failed' })
    original = run.reload.attributes.deep_dup
    summary = run.summary(context.assignments.where(id: assignment.id))
    expect(summary).to include(duration_ms: 1234, requested: 1, processed: 1, failed: 0)
    expect(summary.keys).not_to include(:requested_ids, :outcomes, :account_id, :viewer_id)
    expect(run.reload.attributes).to eq(original)
  end

  it 'reports duration for failed attempts without exposing exception details' do
    run.update!(state: 'failed', outcomes: { assignment.id.to_s => 'processing_failed' }, finished_at: start + 0.456.seconds)
    expect(run.summary(context.assignments)).to include(state: 'failed', duration_ms: 456, processed: 0, failed: 1)
  end

  it 'leaves unfinished or invalid historical timings unavailable while preserving a real zero-duration result' do
    run.update!(finished_at: nil)
    expect(run.summary(context.assignments)[:duration_ms]).to be_nil
    run.update!(state: 'running', finished_at: start + 5.seconds)
    expect(run.summary(context.assignments)[:duration_ms]).to be_nil
    run.update!(state: 'completed', finished_at: start - 1.second)
    expect(run.summary(context.assignments)[:duration_ms]).to be_nil
    run.update!(finished_at: start)
    expect(run.summary(context.assignments)[:duration_ms]).to eq(0)
  end

  it 'does not make a run available across accounts, viewers, signatures or disjoint assignment filters' do
    run
    other = create(:user, account: account, role: :administrator)
    other_context = JrcRelationship::Context.new(account.account_users.find_by!(user: other))
    expect(described_class.latest_for(other_context, other_context.assignments)).to be_nil
    expect(described_class.latest_for(context, context.assignments.where.not(id: assignment.id))).to be_nil
    foreign = create(:account)
    foreign_actor = create(:user, account: foreign, role: :administrator)
    foreign.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    foreign_context = JrcRelationship::Context.new(foreign.account_users.find_by!(user: foreign_actor))
    expect(described_class.latest_for(foreign_context, foreign_context.assignments)).to be_nil
    run.update!(access_signature: 'historical-inaccessible-scope')
    expect(described_class.latest_for(context, context.assignments)).to be_nil
  end
end
