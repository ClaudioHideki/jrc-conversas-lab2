require_relative '../../app/services/jrc_broker/live_ingress_body_limit'

Rails.application.config.middleware.insert_before 0, JrcBroker::LiveIngressBodyLimit

# SQL bind logging uses Base's inspection filter, not the individual model's.
ActiveSupport.on_load(:active_record) do
  self.filter_attributes += [:envelope, :staged_bytes, :origin_context]
end
