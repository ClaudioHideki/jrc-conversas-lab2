require 'rails_helper'

RSpec.describe JrcRelationship::ReviewedPortfolioBatch do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:member) { admin.account_users.find_by!(account: account) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:service) { described_class.new(context) }
  let!(:first) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: admin) }
  let!(:second) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: admin) }
  let(:input) { { 'ids' => [first.id, second.id], 'operation' => 'assign', 'owner_id' => nil, 'request_id' => SecureRandom.uuid } }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'freezes a preview without effects and recovers the exact request after replacement' do
    params = input
    preview = service.preview(params)
    expect([first.reload.owner_id, second.reload.owner_id]).to eq([admin.id, admin.id])
    expect(preview).to include('state' => 'previewed', 'revision' => 1)
    expect(described_class.new(context).preview(params)).to eq(preview)
    expect(preview.fetch('items').pluck('assignment_id')).to eq([first.id, second.id])
    expect { service.preview(params.merge('owner_id' => admin.id)) }.to raise_error(ArgumentError, /conflict/i)
  end

  it 'does not retry unrelated uniqueness failures indefinitely' do
    calls = 0
    allow_any_instance_of(ActiveRecord::Relation).to receive(:create!).and_wrap_original do |method, *args|
      if method.receiver.klass == JrcRelationship::BatchReview && (calls += 1) == 1
        raise ActiveRecord::RecordNotUnique, 'unrelated immutable constraint'
      end
      method.call(*args)
    end
    expect { service.preview(input) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(calls).to eq(1)
  end

  it 'shows the server-resolved responsible person in the frozen review' do
    owner = create(:user, account: account, role: :agent)
    preview = service.preview(input.merge('owner_id' => owner.id))
    expect(preview.fetch('summary')).to include('owner_id' => owner.id, 'owner_name' => owner.name)
  end

  it 'does not claim that a playbook was applied when native conditions filtered out every effect' do
    book = JrcRelationship::Playbook.create!(account: account, name: 'Never eligible', active: true, trigger_kind: 'health',
                                            conditions: [{ 'field' => 'health_score', 'operator' => 'gt', 'value' => 1000 }],
                                            steps: [{ 'kind' => 'activity', 'title' => 'Not eligible', 'after_days' => 0 }])
    preview = service.preview(input.merge('operation' => 'playbook', 'playbook_id' => book.id, 'ids' => [first.id]))
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    result = service.advance(preview.fetch('id'))
    expect(result.fetch('state')).to eq('attention')
    expect(result.fetch('items').first).to include('state' => 'failed', 'receipt' => nil)
    expect(JrcCrm::Activity.where(account: account)).to be_empty
  end

  it 'uses the native activity workflow once and rejects a changed playbook version' do
    book = JrcRelationship::Playbook.create!(account: account, name: 'Native book', active: true, trigger_kind: 'health',
                                            steps: [{ 'kind' => 'activity', 'title' => 'Native follow-up', 'after_days' => 0 }])
    preview = service.preview(input.merge('operation' => 'playbook', 'playbook_id' => book.id))
    book.update!(version: 2)
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /playbook changed/i)
    activity = service.preview(input.merge('operation' => 'activity', 'ids' => [first.id], 'title' => 'Native reviewed activity',
                                           'due_at' => 1.day.from_now.iso8601, 'request_id' => SecureRandom.uuid))
    service.approve(activity.fetch('id'), digest: activity.fetch('digest'))
    2.times { service.advance(activity.fetch('id')) }
    expect(JrcCrm::Activity.where(account: account).pluck(:title)).to eq(['Native reviewed activity'])
  end

  it 'records the real native resources for each successfully applied playbook step without repeating them' do
    book = JrcRelationship::Playbook.create!(account: account, name: 'Verified native book', active: true, trigger_kind: 'health',
                                            steps: [{ 'kind' => 'activity', 'title' => 'Verified follow-up', 'after_days' => 0 }])
    preview = service.preview(input.merge('operation' => 'playbook', 'playbook_id' => book.id, 'ids' => [first.id]))
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    result = service.advance(preview.fetch('id'))
    expect(result.fetch('state')).to eq('completed')
    resource = result.fetch('items').first.fetch('receipt').fetch('resources').sole
    expect(resource).to include('resource_type' => 'JrcRelationship::Action')
    action = JrcRelationship::Action.find(resource.fetch('resource_id'))
    expect(action).to have_attributes(account_id: account.id, assignment_id: first.id)
    expect(action.activity.id).to eq(resource.fetch('activity_id'))
    expect { service.advance(preview.fetch('id')) }.not_to change(JrcCrm::Activity.where(account: account), :count)
  end

  it 'requires the exact reviewed digest and commits a durable receipt per item across restart' do
    preview = service.preview(input)
    expect { service.approve(preview.fetch('id'), digest: '0' * 64) }.to raise_error(ArgumentError, /review/i)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    partial = service.advance(preview.fetch('id'), limit: 1)
    expect(partial.fetch('items').pluck('state')).to eq(%w[applied pending])
    expect([first.reload.owner_id, second.reload.owner_id]).to eq([nil, admin.id])
    done = described_class.new(context).advance(preview.fetch('id'))
    expect(done).to include('state' => 'completed')
    expect(done.fetch('items').map { |item| item.fetch('receipt').fetch('updated') }).to eq([1, 1])
    expect(service.advance(preview.fetch('id'))).to eq(done)
    expect(second.reload.owner_id).to be_nil
  end

  it 'cancels pending work without undoing a receipt that already committed' do
    preview = service.preview(input)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    service.advance(preview.fetch('id'), limit: 1)
    service.cancel(preview.fetch('id'))
    expect(service.advance(preview.fetch('id')).fetch('items').pluck('state')).to eq(%w[applied canceled])
    expect([first.reload.owner_id, second.reload.owner_id]).to eq([nil, admin.id])
  end

  it 'rejects a changed customer snapshot instead of applying stale reviewed choices' do
    preview = service.preview(input)
    first.update!(status: 'at_risk')
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /changed/i)
    expect(first.reload.owner_id).to eq(admin.id)
  end

  it 'rechecks native permissions before the next effect' do
    preview = service.preview(input)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    service.advance(preview.fetch('id'), limit: 1)
    account.disable_features!('jrc_relationship')
    expect { described_class.new(context).advance(preview.fetch('id')) }.to raise_error(Pundit::NotAuthorizedError)
    expect(second.reload.owner_id).to eq(admin.id)
  end

  it 'does not expand an approved audience to another company or an inaccessible assignment' do
    other_account = create(:account)
    foreign = JrcRelationship::Assignment.create!(account: other_account, contact: create(:contact, account: other_account))
    expect { service.preview(input.merge('ids' => [first.id, foreign.id])) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcRelationship::BatchReview.where(account_id: [account.id, other_account.id]).count).to eq(0)
  end

  it 'rejects expired reviews before approval without changing native records' do
    preview = service.preview(input)
    travel 16.minutes do
      expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /expired/i)
    end
    expect([first.reload.owner_id, second.reload.owner_id]).to eq([admin.id, admin.id])
  end

  it 'rolls back an injected native failure and records a failed item without applying the remaining customers' do
    preview = service.preview(input)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    allow_any_instance_of(JrcRelationship::PortfolioBatch).to receive(:call).and_wrap_original do |method|
      method.call
      raise ArgumentError, 'Injected after native SQL'
    end
    result = service.advance(preview.fetch('id'))
    expect(result.fetch('state')).to eq('attention')
    expect(result.fetch('items').pluck('state')).to eq(%w[failed canceled])
    expect(result.fetch('items').pluck('receipt')).to eq([nil, nil])
    expect([first.reload.owner_id, second.reload.owner_id]).to eq([admin.id, admin.id])
  end

  it 'protects a committed item receipt from mutation in PostgreSQL' do
    preview = service.preview(input)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    service.advance(preview.fetch('id'))
    item = JrcRelationship::BatchReview.find(preview.fetch('id')).items.first
    expect do
      item.class.transaction(requires_new: true) { item.update!(receipt: { 'updated' => 999 }) }
    end.to raise_error(ActiveRecord::StatementInvalid, /receipt is immutable/)
  end
end
