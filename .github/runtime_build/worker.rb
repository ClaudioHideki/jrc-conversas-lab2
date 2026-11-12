require '/app/config/environment'
raise 'Synthetic image worker only' unless Rails.env.production? && ENV.fetch('POSTGRES_DATABASE') == 'jrc_runtime_image_test'
class RuntimeBuildProbe
  include Sidekiq::Job
  sidekiq_options queue: ENV.fetch('RUNTIME_SMOKE_QUEUE'), retry: false
  def perform(nonce)
    raise 'Invalid synthetic nonce' unless nonce == ENV.fetch('RUNTIME_SMOKE_NONCE') && nonce.match?(/\A[0-9a-f]{32}\z/)
    raise 'Wrong synthetic database' unless ActiveRecord::Base.connection.select_value('SELECT current_database()') == 'jrc_runtime_image_test'
    receipt = { product_sha: File.read('/app/.git_sha').strip, pid: Process.pid }
    connection = ActiveRecord::Base.connection
    connection.execute('INSERT INTO jrc_runtime_smoke_receipts (nonce, details) VALUES (' + connection.quote(nonce) + ', ' + connection.quote(JSON.generate(receipt)) + '::jsonb)')
    Redis.new(url: ENV.fetch('REDIS_URL')).set('jrc:runtime:receipt:' + nonce, JSON.generate(receipt), ex: 300)
  end
end
