# Native table/validation/counters. New bulk contacts keep the legacy lack of
# create automations/avatar/IP jobs; existing people keep native update events.
# Normal Contact callbacks stay intact. Dirty data belongs to this instance,
# not the canonical wrapper returned by ActiveRecord#becomes.
class JrcCustomers::ImportContact < Contact
  skip_callback :commit, :after, :dispatch_create_event
  skip_callback :commit, :after, :ip_lookup

  def fetch_avatar_from_gravatar
    return if previously_new_record?
    return unless saved_changes.key?('email') && email.present?

    Avatar::AvatarFromGravatarJob.set(wait: 30.seconds).perform_later(becomes(Contact), email)
  end

  private

  def dispatch_update_event
    Rails.configuration.dispatcher.dispatch(CONTACT_UPDATED, Time.zone.now, contact: becomes(Contact), changed_attributes: previous_changes)
  end
end

JrcCustomers::ImportContact.include_mod_with('JrcCustomers::ImportContact')
