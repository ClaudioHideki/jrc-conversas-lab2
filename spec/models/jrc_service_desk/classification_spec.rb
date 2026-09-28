# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk unit classifications', type: :model do
  include_context 'JRC Service Desk domain'

  it 'enforces one active initial status per unit' do
    sd_status
    other = build(:jrc_sd_status, unit: sd_unit)
    expect(other).not_to be_valid
    expect(build(:jrc_sd_status, unit: sd_other_unit)).to be_valid
  end

  it 'does not allow a terminal initial status' do
    expect(build(:jrc_sd_status, unit: sd_unit, phase: 'closed', initial: true)).not_to be_valid
  end

  it 'does not relabel the technical phase of an in-use status' do
    sd_ticket
    expect(sd_status.update(phase: 'closed', initial: false)).to be(false)
  end

  it 'rejects negative priority positions' do
    expect(build(:jrc_sd_priority, unit: sd_unit, position: -1)).not_to be_valid
  end

  it 'enforces code uniqueness within a unit, not across unrelated units' do
    original = create(:jrc_sd_category, unit: sd_unit, code: 'test-code')
    expect(build(:jrc_sd_category, unit: sd_unit, code: original.code)).not_to be_valid
    expect(build(:jrc_sd_category, unit: sd_other_unit, code: original.code)).to be_valid
  end

  it 'rejects a foreign Account team in a queue' do
    expect(build(:jrc_sd_queue, unit: sd_unit, team: create(:team, account: sd_foreign_account))).not_to be_valid
  end
end
