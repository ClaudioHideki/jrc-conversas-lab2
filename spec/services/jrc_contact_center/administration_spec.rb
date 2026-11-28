# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::Administration do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:context) { { account: account, user: actor, account_user: member } }
  let(:access) { JrcContactCenter::AccessScope.new(user_context: context) }
  let(:service) { described_class.new(context: context, access: access) }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    member.update!(custom_role: create(:custom_role, account: account,
                                                     permissions: %w[jrc_contact_center_view jrc_contact_center_configure]))
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', active: true, structure_managed: true)
    JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC-COUNT', name: 'SYNTHETIC observed unit', kind: 'sac')
  end

  it 'isolates a canceled counter query without fabricating zero or losing the other authorized native cards' do
    relation = access.queues
    allow(access).to receive(:queues).and_return(relation)
    allow(relation).to receive(:count).and_raise(ActiveRecord::QueryCanceled, 'SYNTHETIC isolated timeout')
    result = service.call
    failed = result.fetch(:cards).find { |card| card.fetch(:key) == 'queues' }
    observed = result.fetch(:cards).find { |card| card.fetch(:key) == 'general' }
    expect(failed).to include(count: nil, count_error: true)
    expect(observed).to include(count: 1)
    expect(observed).not_to have_key(:count_error)
    expect(result.fetch(:units).pluck(:name)).to eq(['SYNTHETIC observed unit'])
    expect(result.to_json).not_to include('SYNTHETIC isolated timeout')
  end

  it 'does not query or reconstruct cards for permissions the current actor does not possess' do
    member.custom_role.update!(permissions: ['jrc_contact_center_view'])
    expect(service).not_to receive(:count_for)
    expect(service.call.fetch(:cards)).to be_empty
  end

  it 'never converts an authorization failure into a benign unavailable-counter state' do
    relation = access.queues
    allow(access).to receive(:queues).and_return(relation)
    allow(relation).to receive(:count).and_raise(Pundit::NotAuthorizedError)
    expect { service.call }.to raise_error(Pundit::NotAuthorizedError)
  end
end
