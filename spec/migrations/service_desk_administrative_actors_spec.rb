# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk administrative actor schema', type: :model do
  include_context 'JRC Service Desk domain'

  it 'preserves legacy grants and requires an explicit separate purpose for native audit actors' do
    expect(sd_membership.reload.administrative_actor).to be(false)
    connection = ActiveRecord::Base.connection
    column = connection.columns('jrc_service_desk_unit_memberships').find { |entry| entry.name == 'administrative_actor' }
    expect(column.null).to be(false)
    expect(column.default).to eq('false')
    index = connection.indexes('jrc_service_desk_unit_memberships').find { |entry| entry.name == 'jrc_sd_membership_unique' }
    expect(index.unique).to be(true)
    expect(index.columns).to eq(%w[account_id unit_id account_user_id administrative_actor])
    actor_fk = connection.foreign_keys('jrc_service_desk_tickets').find { |entry| entry.options[:name] == 'jrc_sd_ticket_creator_fk' }
    expect(actor_fk).to be_present
  end

  it 'does not allow an audit actor to activate agent access or mutate its ownership purpose' do
    sd_as_admin!
    actor = JrcServiceDesk::OperationalContext.new(sd_context).actor_for(sd_other_unit)
    actor.save!
    expect(actor.active).to be(false)
    actor.active = true
    expect(actor).not_to be_valid
    actor.active = false
    actor.administrative_actor = false
    expect(actor).not_to be_valid
    expect(actor.errors[:administrative_actor]).to include('cannot be changed')
  end

  it 'does not permit an agent to create an administrative actor directly' do
    actor = JrcServiceDesk::UnitMembership.new(account: sd_account, unit: sd_other_unit, account_user: sd_account_user,
                                              administrative_actor: true, active: false, availability: 'unavailable')
    expect(actor).not_to be_valid
    expect(actor.errors[:administrative_actor]).to include('requires the current native Account administrator')
  end
end
