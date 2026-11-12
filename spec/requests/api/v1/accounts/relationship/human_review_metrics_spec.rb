require 'rails_helper'

RSpec.describe 'Relationship human-reviewed alert metrics', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/dashboard" }
  let(:headers) { actor.create_new_auth_token }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  def alert(status = nil, owner: actor)
    assignment = JrcRelationship::Assignment.create!(account: account, owner: owner, contact: create(:contact, account: account))
    member = account.account_users.find_by!(user: owner)
    native_context = JrcRelationship::Context.new(member)
    data = { health: { score: 35, band: 'risk' }, _source_ids: {} }
    record = JrcRelationship::Processor.new(context: native_context, assignment: assignment).action!(
      'health', 'Synthetic monitored evidence', data, native_context.configuration.effective_rules
    )
    return record unless status

    JrcRelationship::Workflow.new(native_context).save(kind: 'actions', id: record.id, attributes: {
                                                         assignment_id: assignment.id, lock_version: record.lock_version,
                                                         alert_review_status: status, alert_review_note: 'Synthetic native human assessment'
                                                       }).fetch(:record)
  end

  def metrics
    get url, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body.fetch('automatic_alert_review')
  end

  it 'keeps the rate unavailable when there are no current human assessments' do
    expect(metrics).to include('reviewed' => 0, 'human_confirmation_percent' => nil)
    alert
    expect(metrics).to include('total' => 1, 'pending' => 1, 'reviewed' => 0, 'human_confirmation_percent' => nil)
  end

  it 'uses only current assessed alerts as the denominator and retains explicit pending coverage' do
    2.times { alert('confirmed') }
    alert('false_positive')
    2.times { alert }
    expect(metrics).to include('total' => 5, 'confirmed' => 2, 'false_positive' => 1, 'pending' => 2,
                               'reviewed' => 3, 'human_confirmation_percent' => 66.7)
  end

  it 'keeps an actual zero rate distinct from missing assessments and excludes stale assessments' do
    record = alert('false_positive')
    expect(metrics).to include('reviewed' => 1, 'human_confirmation_percent' => 0.0)
    JrcRelationship::Workflow.new(context).save(kind: 'actions', id: record.id, attributes: {
                                                  assignment_id: record.assignment_id, lock_version: record.lock_version,
                                                  priority: record.priority + 1
                                                })
    expect(metrics).to include('reviewed' => 0, 'pending' => 1, 'human_confirmation_percent' => nil)
  end

  it 'does not include an inaccessible colleague portfolio or a foreign account in the denominator' do
    alert('confirmed')
    colleague = create(:user, account: account, role: :administrator)
    alert('false_positive', owner: colleague)
    foreign_account = create(:account)
    foreign_account.enable_features!('jrc_customer_master', 'jrc_relationship')
    foreign_user = create(:user, account: foreign_account, role: :administrator)
    foreign_assignment = JrcRelationship::Assignment.create!(account: foreign_account, owner: foreign_user,
                                                             contact: create(:contact, account: foreign_account))
    JrcRelationship::Action.create!(account: foreign_account, assignment: foreign_assignment, owner: foreign_user,
                                    kind: 'health', reason: 'Synthetic foreign evidence', source_key: SecureRandom.uuid,
                                    metadata: { automatic: true, automatic_cause_digest: 'a' * 64 })
    expect(metrics).to include('total' => 1, 'reviewed' => 1, 'human_confirmation_percent' => 100.0)
  end
end
