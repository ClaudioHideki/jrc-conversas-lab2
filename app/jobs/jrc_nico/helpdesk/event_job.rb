class JrcNico::Helpdesk::EventJob < ApplicationJob
  queue_as :default

  def perform(id)
    event = JrcNico::Helpdesk::Event.find(id)
    JrcNico::Helpdesk::EventProcessor.new(event).call
  end
end
