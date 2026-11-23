# frozen_string_literal: true

class JrcCulture::Participations
  class VersionUnavailable < StandardError; end

  def self.enroll!(version, grants)
    now = Time.current
    rows = grants.pluck(:id, :department).map do |grant_id, department|
      { version_id: version.id, grant_id: grant_id, department: department, created_at: now, updated_at: now }
    end
    JrcCulture::Participation.insert_all(rows, unique_by: :idx_culture_participation_identity) if rows.any?
  end

  def initialize(access)
    @access = access
  end

  def confirm!(version_id:, grant_id:)
    @access.account.with_lock('FOR NO KEY UPDATE') do
      grant = @access.employee_grants.find(grant_id)
      version = @access.version_scope.find(version_id)
      participation = @access.own_participations.find_by!(version: version, grant: grant)
      next participation if participation.confirmed_at?

      raise VersionUnavailable unless version.state == 'published'

      participation.update!(confirmed_at: Time.current)
      JrcCulture::Event.record!(@access, 'awareness_confirmed', participation)
      participation
    end
  end
end
