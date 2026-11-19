require 'rails_helper'

RSpec.describe JrcContactCenter::AcwFormQuery do
  let(:account) { create(:account) }
  let(:operator) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:context) { { account: account, account_user: member, user: operator } }
  let(:writer) { JrcContactCenter::AcwFormWrite.new(context: context) }
  let(:definition) { { 'fields' => [{ 'key' => 'detail', 'label' => 'SYNTHETIC field', 'type' => 'text', 'required' => true }] } }
  let(:values) do
    { name: 'SYNTHETIC form', description: 'SYNTHETIC description', status: 'active', definition: definition,
      request_id: SecureRandom.uuid, expected_revision: 0 }
  end
  let(:input) { JrcContactCenter::AcwFormInput.new(**values) }
  let(:scope) { JrcContactCenter::AcwFormAccess.new(context: context) }

  before { account.enable_features!('jrc_contact_center') }

  it 'returns one latest summary per form with bounded pagination and no complete definitions' do
    original = writer.call(input: input)
    updated = JrcContactCenter::AcwFormInput.new(**values, name: 'SYNTHETIC latest', expected_revision: 1, request_id: SecureRandom.uuid)
    writer.call(input: updated, id: original[:form].id)
    result = described_class.new(scope: scope, params: {}).call
    expect(result[:meta]).to eq(page: 1, per_page: 20, total: 1, pages: 1)
    expect(result[:rows].first['form_name']).to eq('SYNTHETIC latest')
    expect(result[:rows].first['form_revision']).to eq(2)
    expect(result[:rows].first.attributes).not_to have_key('definition')
  end

  it 'does not match an obsolete historical name in the current form listing' do
    original = writer.call(input: input)
    updated = JrcContactCenter::AcwFormInput.new(**values, name: 'SYNTHETIC replacement', expected_revision: 1, request_id: SecureRandom.uuid)
    writer.call(input: updated, id: original[:form].id)
    result = described_class.new(scope: scope, params: { q: 'SYNTHETIC form' }).call
    expect(result[:rows]).to be_empty
    expect(result[:meta][:total]).to eq(0)
    expect(original[:version].reload.name).to eq('SYNTHETIC form')
  end

  it 'treats SQL search wildcards as literal characters rather than a request for every form' do
    writer.call(input: JrcContactCenter::AcwFormInput.new(**values, name: 'SYNTHETIC 100%'))
    writer.call(input: JrcContactCenter::AcwFormInput.new(**values, request_id: SecureRandom.uuid))
    result = described_class.new(scope: scope, params: { q: '%' }).call
    expect(result[:rows].map { |row| row['form_name'] }).to eq(['SYNTHETIC 100%'])
    expect(result[:meta][:total]).to eq(1)
  end

  it 'filters the latest explicit archived state without deleting prior versions' do
    original = writer.call(input: input)
    archived = JrcContactCenter::AcwFormInput.new(**values, status: 'archived', expected_revision: 1, request_id: SecureRandom.uuid)
    writer.call(input: archived, id: original[:form].id)
    expect(described_class.new(scope: scope, params: { status: 'active' }).call[:rows]).to be_empty
    result = described_class.new(scope: scope, params: { status: 'archived' }).call
    expect(result[:rows].map(&:id)).to eq([original[:form].id])
    expect(original[:form].versions.count).to eq(2)
  end

  it 'paginates without duplicate rows or silently returning an unbounded list' do
    3.times do |i|
      writer.call(input: JrcContactCenter::AcwFormInput.new(**values, name: "SYNTHETIC #{i}", request_id: SecureRandom.uuid))
    end
    first = described_class.new(scope: scope, params: { per_page: '2' }).call
    second = described_class.new(scope: scope, params: { per_page: '2', page: '2' }).call
    expect(first[:meta]).to eq(page: 1, per_page: 2, total: 3, pages: 2)
    expect(first[:rows].size).to eq(2)
    expect(second[:rows].size).to eq(1)
    expect(first[:rows].map(&:id) & second[:rows].map(&:id)).to be_empty
  end

  it 'caps a requested page size and keeps an out-of-range page empty' do
    writer.call(input: input)
    result = described_class.new(scope: scope, params: { per_page: '999', page: '999' }).call
    expect(result[:meta]).to eq(page: 999, per_page: 100, total: 1, pages: 1)
    expect(result[:rows]).to be_empty
  end

  [{ q: [] }, { status: 'published' }, { status: false }, { page: '-1' }, { page: [] }, { per_page: 1.5 }].each do |params|
    it "rejects invalid native catalogue filter #{params.inspect}" do
      expect { described_class.new(scope: scope, params: params) }.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_form_filter')
    end
  end

  it 'does not grant another account catalogue by accepting its ID as a filter' do
    own = writer.call(input: input)
    other_account = create(:account)
    other_account.enable_features!('jrc_contact_center')
    other = create(:user, :contact_center_eligible, account: other_account, role: :administrator)
    other_context = { account: other_account, account_user: other_account.account_users.find_by!(user: other), user: other }
    foreign = JrcContactCenter::AcwFormWrite.new(context: other_context).call(input: input)
    result = described_class.new(scope: scope, params: { account_id: other_account.id }).call
    expect(result[:rows].map(&:id)).to eq([own[:form].id])
    expect(result[:rows].map(&:id)).not_to include(foreign[:form].id)
  end
end
