require 'rails_helper'

RSpec.describe 'Explicit required ending reason queues', type: :request do
  include_context 'with a frozen ending reason catalogue'

  let(:headers) { actor.create_new_auth_token }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy" }
  let(:payload) do
    { limits: { voice: 180, whatsapp: 180 }, voice_reason_catalog: [entry],
      expected_revision: policy.revision, voice_reason_required_queue_ids: [queue.id.to_s] }
  end

  [nil, false, {}, 'all', [nil], [false], [0], ['01'], ['-1'], ['9223372036854775808']].each do |invalid|
    it "rejects malformed queue selection #{invalid.inspect} without broadening to an account-wide requirement" do
      previous = account.reload.settings.deep_dup
      count = JrcContactCenter::EndingReasonVersion.where(account: account).count
      patch endpoint, headers: headers, params: payload.merge(voice_reason_required_queue_ids: invalid, voice_reason_confirmation: true), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.reload.settings).to eq(previous)
      expect(JrcContactCenter::EndingReasonVersion.where(account: account).count).to eq(count)
    end
  end

  it 'requires a literal confirmation when adding a new queue but not when preserving an already confirmed requirement' do
    configure_ending_reasons!(queues: [])
    [nil, false, 'true', 1].each do |confirmation|
      patch endpoint, headers: headers, params: payload.merge(voice_reason_confirmation: confirmation), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    patch endpoint, headers: headers, params: payload.merge(voice_reason_confirmation: true), as: :json
    expect(response).to have_http_status(:ok)
    revision = response.parsed_body.dig('item', 'revision')
    patch endpoint, headers: headers, params: payload.merge(expected_revision: revision), as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'rejects a real foreign queue identifier without modifying either accounts configuration' do
    foreign = create(:account)
    foreign_unit = JrcContactCenter::Unit.create!(account: foreign, code: 'SYNTHETIC', name: 'SYNTHETIC foreign', kind: 'sac')
    foreign_queue = JrcContactCenter::Queue.create!(account: foreign, unit: foreign_unit, code: 'SYNTHETIC', name: 'SYNTHETIC foreign')
    attributes = payload.merge(voice_reason_required_queue_ids: [foreign_queue.id.to_s], voice_reason_confirmation: true)
    patch endpoint, headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.settings).not_to have_key(JrcContactCenter::AcwPolicy::KEY)
    expect(JrcContactCenter::AcwEndingReasons.new(account: account.reload).call.fetch('required_queue_ids')).to eq([queue.id.to_s])
  end

  it 'does not allow deactivating the final active registered reason while a queue still requires one' do
    previous = account.reload.settings.deep_dup
    patch endpoint, headers: headers, params: payload.merge(voice_reason_catalog: [entry.merge('active' => false)]), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('active_ending_reason_required')
    expect(account.reload.settings).to eq(previous)
  end

  it 'rejects duplicate queue identifiers rather than silently changing the reviewed configuration' do
    patch endpoint, headers: headers, params: payload.merge(voice_reason_required_queue_ids: [queue.id.to_s, queue.id]), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::EndingReasonVersion.where(account: account).count).to eq(1)
  end

  it 'rejects a query replacement for the typed JSON selection even though Rails parsed a queue parameter' do
    request_payload = payload.except(:voice_reason_required_queue_ids)
    patch "#{endpoint}?voice_reason_required_queue_ids[]=#{queue.id}", headers: headers, params: request_payload, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::EndingReasonVersion.where(account: account).count).to eq(1)
  end

  %w[before after].each do |position|
    it "rejects null #{position} a real queue instead of silently accepting a partially filtered selection" do
      ids = position == 'before' ? [nil, queue.id.to_s] : [queue.id.to_s, nil]
      patch endpoint, headers: headers, params: payload.merge(voice_reason_required_queue_ids: ids, voice_reason_confirmation: true), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JrcContactCenter::EndingReasonVersion.where(account: account).count).to eq(1)
    end
  end
end
