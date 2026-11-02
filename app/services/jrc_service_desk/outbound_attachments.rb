# frozen_string_literal: true

# Recheck the existing native author at creation and at the provider boundary.
# Possession of a signed_id never supplies rights to another SD blob owner.
class JrcServiceDesk::OutboundAttachments
  def self.authorize_blob!(blob, user:)
    access = JrcServiceDesk::ProtectedBlobAccess.new(blob: blob, user: user)
    return unless access.protected?
    return if access.allowed?

    raise Pundit::NotAuthorizedError, 'Service Desk attachment access revoked or security scan unavailable'
  end

  def self.authorize_message!(message)
    return if message.private? || (!message.outgoing? && !message.template?)

    user = message.sender if message.sender.is_a?(User)
    user ||= execution_user(message.account_id)
    message.attachments.each do |attachment|
      authorize_blob!(attachment.file.blob, user: user) if attachment.file.attached?
    end
  end

  def self.protected?(message)
    message.attachments.any? do |attachment|
      attachment.file.attached? && JrcServiceDesk::ProtectedBlobAccess.new(blob: attachment.file.blob, user: nil).protected?
    end
  end

  def self.execution_user(account_id)
    user = Current.user
    member = Current.account_user
    user if user.is_a?(User) && member&.account_id == account_id && member.user_id == user.id
  end
end
