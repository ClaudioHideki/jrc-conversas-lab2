require 'rails_helper'

RSpec.describe JrcRelationship::ReviewedCadence do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:member) { admin.account_users.find_by!(account: account) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: contact, owner: admin) }
  let(:book) do
    JrcRelationship::Playbook.create!(account: account, name: 'Reviewed cadence', active: true, trigger_kind: 'no_contact',
                                     steps: [{ 'kind' => 'activity', 'title' => 'First task', 'after_days' => 0 },
                                             { 'kind' => 'meeting', 'title' => 'Follow-up meeting', 'after_days' => 2 }])
  end
  let(:input) do
    { 'ids' => [assignment.id], 'operation' => 'cadence', 'playbook_id' => book.id,
      'conversation_id' => conversation.display_id, 'starts_at' => Time.current.iso8601(6), 'request_id' => SecureRandom.uuid }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  def enroll
    service = JrcRelationship::ReviewedPortfolioBatch.new(context)
    preview = service.preview(input)
    expect(JrcRelationship::CadenceEnrollment.where(account: account).count).to eq(0)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    service.advance(preview.fetch('id'))
    JrcRelationship::CadenceEnrollment.find_by!(account: account)
  end

  it 'freezes a finite native schedule and continues after replacement without repeating receipts or adopting a newer book' do
    enrollment = enroll
    book.update!(version: 2, steps: [{ 'kind' => 'activity', 'title' => 'Different future version', 'after_days' => 0 }])
    described_class.new(context).advance(enrollment.id)
    expect(JrcCrm::Activity.where(account: account).pluck(:title)).to eq(['First task'])
    travel 3.days do
      2.times { described_class.new(context).advance(enrollment.id) }
    end
    expect(enrollment.reload.state).to eq('completed')
    expect(enrollment.steps.order(:ordinal).pluck(:state)).to eq(%w[applied applied])
    expect(JrcCrm::Activity.where(account: account).order(:id).pluck(:title)).to eq(['First task', 'Follow-up meeting'])
  end

  it 'stops pending steps when the selected contact replies' do
    enrollment = enroll
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)
    described_class.new(context).advance(enrollment.id)
    expect(enrollment.reload).to have_attributes(state: 'stopped', stop_reason: 'CONTACT_REPLIED')
    expect(JrcCrm::Activity.where(account: account)).to be_empty
  end

  it 'does not treat a silently imported old message as a new customer reply' do
    enrollment = enroll
    Message.insert_all!([{ account_id: account.id, inbox_id: inbox.id, conversation_id: conversation.id,
                           message_type: Message.message_types.fetch('incoming'), content_type: Message.content_types.fetch('text'),
                           content: 'Historical synthetic text', private: false, sender_type: 'Contact', sender_id: contact.id,
                           source_id: "jrc-history:synthetic:#{SecureRandom.uuid}", created_at: 1.year.ago, updated_at: 1.year.ago }])
    described_class.new(context).advance(enrollment.id)
    expect(JrcCrm::Activity.where(account: account).count).to eq(1)
  end

  it 'stops on human intervention and preserves work committed before cancellation' do
    enrollment = enroll
    described_class.new(context).advance(enrollment.id)
    conversation.update!(status: :resolved)
    travel 3.days do
      described_class.new(context).advance(enrollment.id)
    end
    expect(enrollment.reload.stop_reason).to eq('CONVERSATION_CHANGED')
    expect(enrollment.steps.order(:ordinal).pluck(:state)).to eq(%w[applied canceled])
    expect(JrcCrm::Activity.where(account: account).count).to eq(1)
  end

  it 'cancels explicitly and refuses another tenant or revoked module authority' do
    enrollment = enroll
    other = create(:account)
    other_admin = create(:user, account: other, role: :administrator)
    other.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    foreign = described_class.new(JrcRelationship::Context.new(other_admin.account_users.find_by!(account: other)))
    expect { foreign.get(enrollment.id) }.to raise_error(ActiveRecord::RecordNotFound)
    described_class.new(context).cancel(enrollment.id)
    expect(enrollment.reload.stop_reason).to eq('CANCELED_BY_OPERATOR')
    expect(described_class.new(context).advance(enrollment.id).fetch('state')).to eq('stopped')
    account.disable_features!('jrc_relationship')
    expect { described_class.new(context).advance(enrollment.id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'stops a queued cadence after membership revocation without creating native work' do
    enrollment = enroll
    member.destroy!
    JrcRelationship::CadenceExecutionJob.perform_now(enrollment.id)
    expect(enrollment.reload).to have_attributes(state: 'stopped', stop_reason: 'AUTHORITY_REVOKED')
    expect(JrcCrm::Activity.where(account: account)).to be_empty
  end

  it 'does not silently route an approved cadence to a new portfolio owner' do
    enrollment = enroll
    assignment.update!(owner: create(:user, account: account, role: :agent))
    described_class.new(context).advance(enrollment.id)
    expect(enrollment.reload).to have_attributes(state: 'stopped', stop_reason: 'CUSTOMER_CHANGED')
    expect(JrcCrm::Activity.where(account: account)).to be_empty
  end

  it 'requires the selected conversation to belong to the reviewed customer' do
    stranger = create(:contact, account: account)
    conversation.update!(contact: stranger)
    expect { JrcRelationship::ReviewedPortfolioBatch.new(context).preview(input) }.to raise_error(ArgumentError, /selected customer/)
    expect(JrcRelationship::CadenceEnrollment.where(account: account)).to be_empty
  end

  it 'keeps the frozen schedule and committed receipt immutable in PostgreSQL' do
    enrollment = enroll
    described_class.new(context).advance(enrollment.id)
    step = enrollment.steps.order(:ordinal).first
    expect do
      enrollment.class.transaction(requires_new: true) { enrollment.update!(snapshot: {}) }
    end.to raise_error(ActiveRecord::StatementInvalid, /snapshot is immutable/)
    expect do
      step.class.transaction(requires_new: true) { step.update!(receipt: { 'resource_id' => -1 }) }
    end.to raise_error(ActiveRecord::StatementInvalid, /receipt is immutable/)
  end
end
