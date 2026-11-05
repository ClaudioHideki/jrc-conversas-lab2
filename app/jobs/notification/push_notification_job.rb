class Notification::PushNotificationJob < ApplicationJob
  queue_as :default

  def perform(notification)
    return unless notification.visible_to_user?

    Notification::PushNotificationService.new(notification: notification).perform
  end
end
