# Run for a single original. A review fingerprint must be explicitly supplied
# to change the terminal payload. Neither mode schedules the original.
repair = JrcBroker::TerminalConversationRepair.new(
  account_id: Integer(ENV.fetch('JRC_ACCOUNT_ID')), inbox_id: Integer(ENV.fetch('JRC_INBOX_ID')),
  message_id: Integer(ENV.fetch('JRC_MESSAGE_ID')), delivery_id: ENV.fetch('JRC_DELIVERY_ID')
)
mode = ENV.fetch('JRC_TERMINAL_MODE', 'review')
abort 'invalid terminal mode' unless %w[review correct].include?(mode)
puts repair.perform(expected_sha256: mode == 'correct' ? ENV.fetch('JRC_REVIEW_SHA256') : nil).to_json
