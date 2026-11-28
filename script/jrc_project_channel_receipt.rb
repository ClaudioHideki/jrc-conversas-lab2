# Rails runner. One original, one authenticated evidence file and its independently
# pinned SHA-256. Defaults to review. Never pass raw proof material through logs.
mode = ENV.fetch('RECEIPT_MODE', 'review')
abort 'invalid receipt mode' unless %w[review apply].include?(mode)
bytes = File.binread(ENV.fetch('RECEIPT_FILE'), 65_537)
abort 'oversized receipt' if bytes.bytesize > 65_536
digest = Digest::SHA256.hexdigest(bytes)
abort 'receipt digest mismatch' unless digest == ENV.fetch('RECEIPT_FILE_SHA256')
input = JSON.parse(bytes)
outcome = JrcBroker::ProjectionReceipt.new(input, digest).perform(apply: mode == 'apply')
puts({message_id: input.fetch('message_id'), result: outcome, evidence_sha256: digest}.to_json)
