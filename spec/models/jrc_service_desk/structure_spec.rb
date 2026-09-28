# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'JRC Service Desk operational structure', type: :model do
  include_context 'JRC Service Desk domain'

  it 'supports several operators per Account and several units per operator' do
    second = create(:jrc_sd_operator_company, account: sd_account)
    expect(sd_operator.units).to contain_exactly(sd_unit)
    expect(create(:jrc_sd_unit, operator_company: second).account).to eq(sd_account)
    expect(sd_other_unit.operator_company).to eq(sd_operator)
  end

  it 'rejects a unit whose operator belongs to another Account' do
    unit = build(:jrc_sd_unit, account: sd_account, operator_company: sd_foreign_operator)
    expect(unit).not_to be_valid
    expect(unit.errors[:operator_company]).to be_present
  end

  it 'rejects an AccountUser from another Account' do
    foreign = create(:account_user, account: sd_foreign_account)
    membership = build(:jrc_sd_membership, unit: sd_unit, account_user: foreign)
    expect(membership).not_to be_valid
    expect(membership.errors[:account_user]).to be_present
  end

  it 'rejects a membership with a unit from another Account' do
    membership = build(:jrc_sd_membership, account: sd_account, unit: sd_foreign_unit, account_user: sd_account_user)
    expect(membership).not_to be_valid
  end

  it 'does not grant scope by the database default' do
    expect(JrcServiceDesk::UnitMembership.new.active).to be(false)
  end

  it 'does not create roles or permissions on the membership' do
    expect(JrcServiceDesk::UnitMembership.column_names & %w[roles role permissions custom_role_id]).to be_empty
  end

  it 'does not allow duplicate grants for the same AccountUser/unit' do
    duplicate = build(:jrc_sd_membership, unit: sd_unit, account_user: sd_account_user)
    expect(duplicate).not_to be_valid
  end

  it 'does not move an existing unit into a different operator' do
    second = create(:jrc_sd_operator_company, account: sd_account)
    expect(sd_unit.update(operator_company: second)).to be(false)
    expect(sd_unit.reload.operator_company_id).to eq(sd_operator.id)
  end

  it 'does not move an existing membership into another unit' do
    expect(sd_membership.update(unit: sd_other_unit)).to be(false)
  end

  it 'keeps native customer and routing models distinct' do
    expect(sd_operator).not_to be_a(Company)
    expect(sd_unit).not_to be_a(Team)
    expect(JrcServiceDesk::Unit.reflect_on_association(:operator_company).klass).to eq(JrcServiceDesk::OperatorCompany)
  end
end
