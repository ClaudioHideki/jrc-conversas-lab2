# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Authorized recording links to existing native ending actions', :pabx do
  include_context 'with native authorized quality review source'

  let(:path) { "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings/#{record.id}/ending_context" }
  let(:headers) { actor.create_new_auth_token }
  let(:qualification) do
    JrcContactCenter::Qualification.create!(account: account, account_user: member, call_session: source_call,
                                            channel: 'voice', notes: 'SYNTHETIC private ACW notes')
  end

  before { role.update!(permissions: recording_rights + ['jrc_contact_center_operate']) }

  def other_qualification
    other = create(:user, account: account)
    participant = account.account_users.find_by!(user: other)
    JrcContactCenter::Qualification.create!(account: account, account_user: participant, call_session: source_call, channel: 'voice')
  end

  it 'returns an actual empty read without creating ACW, querying Nico, starting audio or dispatching actions' do
    expect(JrcContactCenter::QualificationManager).not_to receive(:ensure_voice!)
    expect(provider).not_to receive(:find_analysis)
    expect do
      get path, headers: headers, as: :json
    end.not_to change(JrcContactCenter::Qualification, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('account_id' => account.id.to_s, 'recording_id' => record.id.to_s,
                                            'call_session_id' => source_call.id.to_s, 'call_id' => record.external_unique_id,
                                            'items' => [], 'meta' => { 'page' => 1, 'per_page' => 20, 'total' => 0, 'pages' => 0 })
    expect(response.headers.fetch('Cache-Control')).to include('private', 'no-store')
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingActionOrigin.where(account: account)).to be_empty
  end

  it 'returns only the native minimal own qualification identity without private notes or invented completion' do
    original = qualification.attributes
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole).to eq('id' => qualification.id.to_s, 'account_user_id' => member.id.to_s,
                                                          'started_at' => nil, 'completed_at' => nil)
    expect(response.body).not_to include('SYNTHETIC private ACW notes', 'recording_reference', 'synthetic-password')
    expect(qualification.reload.attributes).to eq(original)
  end

  it 'does not disclose another agent qualification through recording-listen or native administrator status' do
    hidden = other_qualification
    member.update!(role: :administrator)
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(0)
    expect(response.body).not_to include("\"id\":\"#{hidden.id}\"")
  end

  it 'requires current operate or native full-access audit authority independently of listening and review rights' do
    qualification
    role.update!(permissions: recording_rights + ['jrc_contact_center_quality_review'])
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('account_user_id', 'SYNTHETIC private ACW notes')
  end

  it 'requires listening authority independently of operating or native audit authority' do
    qualification
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_operate jrc_contact_center_audit])
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('account_user_id')
  end

  it 'allows another agent history only through the existing supervisor plus audit authority and rechecks it on withdrawal' do
    other = other_qualification
    role.update!(permissions: recording_rights + %w[jrc_contact_center_supervise jrc_contact_center_audit])
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole.fetch('id')).to eq(other.id.to_s)
    role.update!(permissions: recording_rights + ['jrc_contact_center_supervise'])
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('account_user_id')
  end

  it 'keeps accounts and current corporate units isolated and does not trust caller-selected identities' do
    qualification
    get path, headers: headers, params: { user_id: 999_999, qualification_id: 999_999, unit_id: 999_999 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole.fetch('id')).to eq(qualification.id.to_s)
    foreign = create(:account)
    get path.sub("accounts/#{account.id}", "accounts/#{foreign.id}"), headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    account.jrc_crm_user_business_units.where(user: actor).find_each { |coverage| coverage.update!(active: false) }
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects malformed pages instead of silently loading another context or writing a qualification' do
    get path, headers: headers, params: { page: '1;SELECT' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('invalid_ending_history_page')
    expect(JrcContactCenter::Qualification.where(account: account)).to be_empty
  end

  it 'paginates twenty actual authorized qualifications without exposing excluded agents in the count' do
    21.times { other_qualification }
    role.update!(permissions: recording_rights + %w[jrc_contact_center_supervise jrc_contact_center_audit])
    get path, headers: headers, params: { page: 1 }
    first = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(first.fetch('items').size).to eq(20)
    expect(first.fetch('meta')).to eq('page' => 1, 'per_page' => 20, 'total' => 21, 'pages' => 2)
    get path, headers: headers, params: { page: 2 }
    second = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(second.fetch('items').size).to eq(1)
    ids = first.fetch('items').map { |row| row.fetch('id') } + second.fetch('items').map { |row| row.fetch('id') }
    expect(ids.uniq.size).to eq(21)
    expect(JrcContactCenter::EndingActionOrigin.where(account: account)).to be_empty
  end
end
