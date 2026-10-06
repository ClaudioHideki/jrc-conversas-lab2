namespace :jrc_relationship do
  desc 'Diagnose eligible existing customers; APPLY=true explicitly applies idempotent post-sale backfill'
  task backfill: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    member = account.account_users.find_by!(user_id: ENV.fetch('ACTOR_ID'))
    context = JrcRelationship::Context.new(member)
    raise ArgumentError, 'APPLY must be true or false' unless %w[true false].include?(ENV.fetch('APPLY', 'false'))
    Time.use_zone(Time.find_zone(account.reporting_timezone) || Time.zone) do
      puts JSON.pretty_generate(JrcRelationship::Backfill.new(context: context).call(apply: ENV['APPLY'] == 'true'))
    end
  end
end
