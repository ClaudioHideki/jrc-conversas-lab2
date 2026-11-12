require_relative '../../app/services/jrc_broker/history_media_body_limit'

Rails.application.config.middleware.insert_before 0, JrcBroker::HistoryMediaBodyLimit
