# frozen_string_literal: true

FactoryBot.define do
  factory :account_user do
    account
    user
    role { 'agent' }

    trait :contact_center_eligible do
      after(:create) do |member|
        JrcContactCenter::AccessGrant.create!(account: member.account, account_user: member, eligible: true)
      end
    end
  end
end
