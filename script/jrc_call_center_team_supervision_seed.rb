require_relative 'jrc_call_center_synthetic_password'

# Only the parent synthetic runner invokes this; none of these grants are operational defaults.
class JrcContactCenter::SyntheticTeamSupervisionSeed
  def self.call(account:, unit:)
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.database == 'jrc_sd_bc_portal_concurrency_20261025_test' && config.configuration_hash[:host] == '127.0.0.1'
    raise 'Owned synthetic team supervision runner required' unless owned

    new(account, unit).call
  end

  def initialize(account, unit)
    @account = account
    @unit = unit
  end

  def call
    team = @account.teams.create!(name: 'SYNTHETIC equipe de supervisão com nome extenso para a conferência de responsividade')
    @account.jrc_crm_team_scopes.create!(team: team, scope: 'BUSINESS_UNIT', business_unit_id: @unit.settings.fetch('business_unit_id'))
    permissions = %w[jrc_contact_center_view jrc_contact_center_supervise]
    role = CustomRole.create!(account: @account, name: 'SYNTHETIC explicit supervisors only', permissions: permissions)
    primary = create_member('principal com nome extenso para revisão do gestor', role)
    additional = create_member('adicional', role)
    [primary, additional].each do |member|
      JrcContactCenter::AccessGrant.create!(account: @account, account_user: member, eligible: true)
      @account.jrc_crm_user_business_units.create!(user: member.user, scope: 'BUSINESS_UNIT', structure_managed: true,
                                                 business_unit_id: @unit.settings.fetch('business_unit_id'))
    end
    20.times { |index| create_member("pessoa sem concessão #{index}", nil) }
    { team_id: team.id.to_s, team_name: team.name, primary_supervisor_id: primary.id.to_s, primary_supervisor_name: primary.user.name,
      additional_supervisor_id: additional.id.to_s, additional_supervisor_name: additional.user.name }
  end

  private

  def create_member(name, role)
    user = User.new(name: "SYNTHETIC supervisor #{name}", email: "cc-supervision-#{SecureRandom.hex(8)}@example.test",
                    password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
    user.skip_confirmation_notification!
    user.save!
    AccountUser.create!(account: @account, user: user, role: :agent, custom_role: role)
  end
end
