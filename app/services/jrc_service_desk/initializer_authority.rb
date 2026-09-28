# frozen_string_literal: true

# A server-side nominative designation, NOT a login, role, feature or public grant API.
# Empty/malformed configuration denies everyone. Existing native staff sessions only.
class JrcServiceDesk::InitializerAuthority
  CONFIG_KEY = 'JRC_SERVICE_DESK_INITIALIZER_USER_IDS'

  def self.ids(raw = ENV.fetch(CONFIG_KEY, ''))
    return [] unless raw.is_a?(String) && !raw.strip.empty?
    values = raw.split(',', -1).map(&:strip)
    return [] unless values.all? { |v| v.match?(/\A[1-9][0-9]{0,18}\z/) && v.to_i <= 9_223_372_036_854_775_807 }
    values.map(&:to_i).uniq
  end

  def self.authorized?(actor)
    return false unless actor.is_a?(::SuperAdmin) && actor.persisted? && ids.include?(actor.id)
    ::SuperAdmin.where(id: actor.id).where.not(confirmed_at: nil).exists?
  end

  def self.client_user?(user)
    user.is_a?(::User) && user.persisted? && user.type.blank? && user.confirmed_at.present? && !ids.include?(user.id)
  end
end
