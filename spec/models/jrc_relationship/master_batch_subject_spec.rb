require 'rails_helper'

# These cases deliberately bypass Rails validation to prove the PostgreSQL
# tenant, snapshot and receipt guards, each within a rollback savepoint.
# rubocop:disable Rails/SkipsModelValidations
RSpec.describe 'Native reviewed batch subject constraints', type: :model do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:company) { account.master_companies.create!(name: 'Synthetic master batch subject') }
  let(:other_company) { account.master_companies.create!(name: 'Synthetic other master subject') }
  let(:master) do
    JrcRelationship::BatchReview.create!(account: account, actor: actor, request_id: SecureRandom.uuid,
                                         inputs: { 'operation' => 'master_allocation', 'ids' => [company.id] },
                                         snapshot: { 'version' => 1, 'rows' => [{ 'company_id' => company.id, 'label' => company.name }] },
                                         digest: 'c' * 64, expires_at: 15.minutes.from_now)
  end
  let(:legacy) do
    JrcRelationship::BatchReview.create!(account: account, actor: actor, request_id: SecureRandom.uuid,
                                         inputs: { 'operation' => 'activity', 'ids' => [allocation.id] },
                                         snapshot: { 'version' => 1, 'rows' => [{ 'assignment_id' => allocation.id }] },
                                         digest: 'd' * 64, expires_at: 15.minutes.from_now)
  end
  let(:allocation) { JrcRelationship::Assignment.create!(account: account, owner: actor, company: company) }
  let(:pending_item) { master.items.create!(account: account, company: company, ordinal: 0) }
  let(:receipt) { { 'operation' => 'master_allocation', 'company_id' => company.id, 'assignment_id' => allocation.id } }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'can store a same-account master company as a pending subject without creating a customer allocation' do
    company
    expect { pending_item }.not_to change(JrcRelationship::Assignment, :count)
    expect(pending_item).to have_attributes(state: 'pending', company_id: company.id, assignment_id: nil, receipt: nil)
  end

  it 'retains the original required assignment shape for assignment-only operations even when model validation is bypassed' do
    row = legacy.items.create!(account: account, assignment: allocation, ordinal: 0)
    expect do
      row.transaction(requires_new: true) { row.update_columns(assignment_id: nil, state: 'canceled') }
    end.to raise_error(ActiveRecord::StatementInvalid, /Batch receipt is immutable/)
    expect(row.reload).to have_attributes(assignment_id: allocation.id, company_id: nil, state: 'pending')
  end

  it 'does not allow a master company subject to be inserted under an original operation' do
    parent = legacy
    expect do
      JrcRelationship::BatchItem.transaction(requires_new: true) do
        JrcRelationship::BatchItem.insert_all!([{ account_id: account.id, batch_review_id: parent.id,
                                                  company_id: company.id, ordinal: 0, state: 'pending' }])
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /requires a pending native master review/)
  end

  it 'rejects a foreign company with the actual composite account/company foreign key' do
    parent = master
    foreign = create(:account).master_companies.create!(name: 'Synthetic foreign master subject')
    expect do
      JrcRelationship::BatchItem.transaction(requires_new: true) do
        JrcRelationship::BatchItem.insert_all!([{ account_id: account.id, batch_review_id: parent.id,
                                                  company_id: foreign.id, ordinal: 0, state: 'pending' }])
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey, /rel_batch_master_tenant/)
    expect(parent.items).to be_empty
  end

  it 'freezes the pending master company identity before a cancellation or failure receipt' do
    row = pending_item
    replacement = other_company
    expect do
      row.transaction(requires_new: true) { row.update_columns(company_id: replacement.id, state: 'canceled') }
    end.to raise_error(ActiveRecord::StatementInvalid, /Master batch receipt is immutable/)
    expect(row.reload).to have_attributes(company_id: company.id, assignment_id: nil, state: 'pending')
  end

  it 'binds the native assignment exactly once at applied receipt commit and preserves the terminal receipt' do
    row = pending_item
    row.update!(state: 'applied', assignment: allocation, receipt: receipt)
    original = row.reload.attributes
    expect do
      row.transaction(requires_new: true) { row.update_columns(receipt: receipt.merge('changed' => true)) }
    end.to raise_error(ActiveRecord::StatementInvalid, /Master batch receipt is immutable/)
    expect(row.reload.attributes).to eq(original)
  end

  it 'does not accept the allocation of a different company even within the same account' do
    row = pending_item
    other = JrcRelationship::Assignment.create!(account: account, owner: actor, company: other_company)
    expect do
      row.transaction(requires_new: true) do
        row.update_columns(state: 'applied', assignment_id: other.id, receipt: receipt.merge('assignment_id' => other.id))
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /must identify its exact native company allocation/)
    expect(row.reload).to have_attributes(state: 'pending', assignment_id: nil, receipt: nil)
  end

  it 'does not attach an allocation to a failed subject' do
    row = pending_item
    target = allocation
    expect do
      row.transaction(requires_new: true) { row.update_columns(state: 'failed', assignment_id: target.id) }
    end.to raise_error(ActiveRecord::StatementInvalid, /rel_batch_subject_shape/)
    expect(row.reload).to have_attributes(state: 'pending', assignment_id: nil)
  end

  it 'keeps the original frozen review snapshot guard and rejects duplicate companies in one review' do
    row = pending_item
    expect do
      master.transaction(requires_new: true) { master.update_columns(snapshot: { 'changed' => true }, revision: master.revision + 1) }
    end.to raise_error(ActiveRecord::StatementInvalid, /Reviewed batch snapshot is immutable/)
    expect do
      row.transaction(requires_new: true) { master.items.create!(account: account, company: company, ordinal: 1) }
    end.to raise_error(ActiveRecord::RecordNotUnique, /rel_batch_master_once/)
    expect(master.items.pluck(:company_id, :state)).to eq([[company.id, 'pending']])
  end
end
# rubocop:enable Rails/SkipsModelValidations
