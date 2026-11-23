# frozen_string_literal: true

namespace :jrc_culture do
  desc 'Grant or revoke the Manual de Cultura administrator role for an existing scoped account membership'
  task administrator: :environment do
    values = %w[ACCOUNT_ID ACTOR_ID MEMBER_ID UNIT_ID].to_h { |key| [key, Integer(ENV.fetch("JRC_CULTURE_#{key}"), 10)] }
    action = ENV.fetch('JRC_CULTURE_ACTION')
    abort 'Use JRC_CULTURE_ACTION=grant or revoke' unless %w[grant revoke].include?(action)

    account = Account.find(values.fetch('ACCOUNT_ID'))
    actor = account.account_users.administrator.find_by!(user_id: values.fetch('ACTOR_ID')).user
    member = account.account_users.find(values.fetch('MEMBER_ID'))
    unit = account.jrc_crm_business_units.active.find(values.fetch('UNIT_ID'))
    unless account.active? && actor.active_for_authentication? &&
           JrcCrm::CorporateCoverage.new(account: account, user: actor).unit_allowed?(unit.id)
      abort 'Actor must be an active native administrator with coverage for this unit'
    end
    if action == 'grant' && !(member.user.active_for_authentication? &&
                              JrcCrm::CorporateCoverage.new(account: account, user: member.user).unit_allowed?(unit.id))
      abort 'Target must be an active account member with coverage for this unit'
    end

    account.with_lock('FOR NO KEY UPDATE') do
      grants = JrcCulture::Grant.where(account: account, unit: unit, member_key: member.id, role: 'administrator')
      grant = action == 'grant' ? grants.first_or_initialize : grants.first!
      grant.account_user = member if grant.new_record?
      grant.update!(active: action == 'grant')
      JrcCulture::Event.create!(account: account, actor_id: actor.id, action: "administrator_#{action}",
                                subject_type: grant.class.name, subject_id: grant.id)
      puts "Manual de Cultura: #{action} (grant_id=#{grant.id})"
    end
  end
end
