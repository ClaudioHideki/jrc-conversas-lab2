# frozen_string_literal: true

require 'rails_helper'

# Source coverage only. Public configure and private destination permissions are
# separate mandatory checks, not grants conferred by this internal reader.
RSpec.describe JrcContactCenter::EndingActions::RuleSourceAuthority do
  include_context 'with native ending rule configuration'

  let(:saved_rule) do
    configure_native_ending_rule
    JrcContactCenter::EndingActions::Catalogue.new(account: account).call.fetch('entries').sole
  end
  let(:authority) { described_class.new(account: account, member: member) }
  let(:second_business) do
    JrcCrm::BusinessUnit.create!(account: account, operating_company: issuer, code: 'SYNTHETIC_EDITOR_OTHER',
                                 name: 'SYNTHETIC separate configuration scope', active: true)
  end

  before { saved_rule }

  def restrict_source_to_business(target)
    JrcCrm::UserBusinessUnit.where(account: account, user: actor, scope: 'GROUP').find_each { |row| row.update!(active: false) }
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: issuer,
                                     business_unit: target, active: true, structure_managed: true)
  end

  it 'preserves existing whole-account source coverage without changing the saved rule or native records' do
    expect(authority.call(saved_rule)).to eq(saved_rule)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(1)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'permits a saved source only within the currently authorized business unit' do
    restrict_source_to_business(business)
    expect(authority.call(saved_rule)).to eq(saved_rule)
    expect(JrcCrm::UserBusinessUnit.where(account: account, user: actor, scope: 'GROUP', active: true)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rejects another business unit even when the rule and original queue identifiers are known' do
    restrict_source_to_business(second_business)
    expect { authority.call(saved_rule) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(1)
  end

  it 'rechecks current queue coverage independently of an old authorized saved scope' do
    other = JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC_REMAPPED_EDITOR', name: 'SYNTHETIC remapped source', kind: 'sac',
                                           settings: { 'issuer_company_id' => issuer.id.to_s, 'business_unit_id' => second_business.id.to_s })
    queue.update!(unit: other)
    restrict_source_to_business(business)
    expect { authority.call(saved_rule) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not retain source access after corporate coverage is withdrawn' do
    JrcCrm::UserBusinessUnit.where(account: account, user: actor, active: true).find_each { |row| row.update!(active: false) }
    expect { authority.call(saved_rule) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(1)
  end

  it 'does not accept a foreign account membership as a configurator of this account' do
    other = create(:user, :contact_center_eligible, account: create(:account))
    foreign = AccountUser.find_by!(user: other)
    expect { described_class.new(account: account, member: foreign) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end
end
