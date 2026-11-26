# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActions::ConfigurationContext do
  include_context 'with native ending rule configuration'

  before do
    JrcCrm::UserBusinessUnit.where(account: account, user: actor, scope: 'GROUP').find_each { |row| row.update!(active: false) }
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: issuer,
                                     business_unit: business, active: true, structure_managed: true)
  end

  it 'keeps the global writer denied under business-unit-only coverage' do
    reached = false
    expect { described_class.new(account: account, member: member).call { reached = true } }.to raise_error(Pundit::NotAuthorizedError)
    expect(reached).to be false
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end

  it 'permits only the explicit per-rule context with native configure and an existing mapped coverage' do
    result = described_class.new(account: account, member: member, for_rule: true).call do |fresh|
      [fresh.id, Current.account.id, Current.account_user.id, Current.user.id]
    end
    expect(result).to eq([member.id, account.id, member.id, actor.id])
    expect(JrcCrm::UserBusinessUnit.where(account: account, user: actor, scope: 'GROUP', active: true)).to be_empty
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'restores the previous native context even if a scoped caller raises' do
    previous = JrcServiceDesk::NativeExecutionContext::FIELDS.index_with { |field| Current.public_send(field) }
    command = described_class.new(account: account, member: member, for_rule: true)
    expect { command.call { raise ArgumentError, 'SYNTHETIC scoped caller rejection' } }.to raise_error(ArgumentError)
    expect(previous.keys.index_with { |field| Current.public_send(field) }).to eq(previous)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end

  it 'does not treat business coverage as native configure permission' do
    command = described_class.new(account: account, member: member, for_rule: true)
    member.update!(custom_role: create(:custom_role, account: account, permissions: %w[jrc_contact_center_view]))
    expect { command.call {} }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end

  it 'revalidates current coverage rather than trusting the membership supplied at construction' do
    command = described_class.new(account: account, member: member, for_rule: true)
    JrcCrm::UserBusinessUnit.where(account: account, user: actor, active: true).find_each { |row| row.update!(active: false) }
    expect { command.call {} }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end

  it 'requires an enabled native Call Center independently of scoped corporate access' do
    command = described_class.new(account: account, member: member, for_rule: true)
    account.disable_features!('jrc_contact_center')
    expect { command.call {} }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end
end
