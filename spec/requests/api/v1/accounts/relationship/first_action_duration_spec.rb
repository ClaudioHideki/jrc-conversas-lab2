require 'rails_helper'

RSpec.describe 'Relationship observed first-action durations', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/dashboard" }
  let(:headers) { actor.create_new_auth_token }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  def record(seconds: nil, portfolio: assignment, measured_at: Time.current)
    metadata = seconds.nil? ? {} : { first_action_elapsed_seconds: seconds }
    JrcRelationship::Action.create!(account: portfolio.account, assignment: portfolio, owner: portfolio.owner, kind: 'manual',
                                    reason: 'Synthetic historical reaction observation', source_key: SecureRandom.uuid,
                                    first_action_at: measured_at, metadata: metadata)
  end

  def minutes
    get url, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body.fetch('first_action_minutes')
  end

  it 'preserves actual native calendar evidence rather than substituting wall time or missing values' do
    travel_to Time.current.change(usec: 0) do
      action = record(measured_at: nil)
      action.update!(sla_started_at: 2.minutes.ago)
      JrcOperations::SlaClock.new(action).mark_first_action!
      expect(action.reload.metadata.fetch('first_action_elapsed_seconds')).to eq(120)
      expect(minutes).to eq(2.0)
    end
  end

  it 'keeps missing and malformed historical durations unavailable without breaking the dashboard' do
    [nil, 'not measured', 'NaN', 'Infinity', -60, { state: 'unknown' }].each { |value| record(seconds: value) }
    expect(minutes).to be_nil
  end

  it 'averages finite observations including genuine zero and legacy numeric strings, excluding invalid text' do
    [0, 120, '240', '1_2_0', '0x78', '0o170', '0b1111000', 'not measured', 'NaN', '1e9999'].each { |value| record(seconds: value) }
    expect(minutes).to eq(2.0)
  end

  it 'does not parse inaccessible portfolio observations or observations outside the selected account and period' do
    record(seconds: 120)
    colleague = create(:user, account: account, role: :administrator)
    hidden = JrcRelationship::Assignment.create!(account: account, owner: colleague, contact: create(:contact, account: account))
    record(seconds: 'hidden invalid duration', portfolio: hidden)
    foreign = create(:account)
    foreign_user = create(:user, account: foreign, role: :administrator)
    foreign_portfolio = JrcRelationship::Assignment.create!(account: foreign, owner: foreign_user, contact: create(:contact, account: foreign))
    record(seconds: 'foreign invalid duration', portfolio: foreign_portfolio)
    record(seconds: 'old invalid duration', measured_at: 100.days.ago)
    expect(minutes).to eq(2.0)
  end

  it 'keeps the mean finite without overflowing a floating-point running sum' do
    3.times { record(seconds: '1e308') }
    expect(minutes).to be_finite
    expect(minutes).to be_within(1e293).of(1e308 / 60)
  end
end
