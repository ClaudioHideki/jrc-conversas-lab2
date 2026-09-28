# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::Base, type: :model do
  it 'is abstract and uses the native ApplicationRecord' do
    expect(described_class.abstract_class?).to be(true)
    expect(described_class.superclass).to eq(ApplicationRecord)
  end

  it 'requires the native Account without creating another tenant model' do
    reflection = described_class.reflect_on_association(:account)
    expect(reflection.klass).to eq(Account)
    expect(reflection.options[:optional]).to be(false)
  end

  it 'reserves a distinct table prefix' do
    expect(JrcServiceDesk.table_name_prefix).to eq('jrc_service_desk_')
  end
end
