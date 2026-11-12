# Synthetic production-image probe. No external provider or customer environment.
require 'json'
require 'digest'
require 'open3'
require 'securerandom'
require 'fileutils'

out = ENV.fetch('RUNTIME_SMOKE_OUTPUT')
nonce = ENV.fetch('RUNTIME_SMOKE_NONCE')
raise 'Synthetic nonce required' unless nonce.match?(/\A[0-9a-f]{32}\z/)
raise 'Production image boot required' unless Rails.env.production?
raise 'Wrong source image' unless File.read('/app/.git_sha').strip == ENV.fetch('RUNTIME_PRODUCT_SHA')
database = ActiveRecord::Base.connection.select_value('SELECT current_database()')
raise 'Exclusive synthetic database required' unless database == 'jrc_runtime_image_test'
raise 'Owned Redis required' unless URI(ENV.fetch('REDIS_URL')).host.start_with?('jrc-runtime-')
report = { phase: ARGV.fetch(0), product_sha: ENV.fetch('RUNTIME_PRODUCT_SHA'), checks: [], passed: false }
def command!(*args)
  stdout, stderr, status = Open3.capture3(*args)
  raise "Native command failed: #{args.first}" unless status.success?
  stdout
end
begin
  case ARGV.fetch(0)
  when 'native'
    raise 'Ruby runtime differs' unless RUBY_VERSION == '3.4.12' && RUBY_PATCHLEVEL == 148 && RUBY_PLATFORM.include?('musl')
    raise 'Alpine runtime differs' unless File.read('/etc/alpine-release').start_with?('3.24.')
    raise 'Node runtime differs' unless command!('node', '--version').strip == 'v24.22.3'
    report[:checks] << 'alpine_ruby_node_musl'
    require 'pg'
    require 'nokogiri'
    require 'grpc'
    require 'ffi'
    require 'google/protobuf'
    require 'vips'
    require 'bigdecimal'
    raise 'Decimal regression' unless BigDecimal('0.1') + BigDecimal('0.2') == BigDecimal('0.3')
    raise 'Native XML regression' unless Nokogiri::XML('<probe>JRC</probe>').at('probe').text == 'JRC'
    raise 'Native image regression' unless Vips::Image.black(2, 2).width == 2
    report[:native_versions] = { pg: PG.library_version, vips: Vips.version_string,
      rails: Rails.version, sidekiq: Sidekiq::VERSION, grpc: GRPC::VERSION,
      nokogiri: Nokogiri::VERSION, ffi: FFI::VERSION }
    report[:checks] << 'native_libraries_and_decimal'
    command!('sh', '-c', 'ldd /usr/local/bin/ruby && ldd /usr/local/bin/node')
    raise 'Rails/Sidekiq version differs' unless Rails.version == '7.1.5.2' && Sidekiq::VERSION == '7.3.1'
    raise 'Model loading failed' unless Account.table_exists? && Contact.table_exists? && Conversation.table_exists? && JrcCrm::BackofficeRequest.table_exists?
    report[:checks] << 'rails_production_and_integrated_models'
    require 'prawn'
    regular = ['/usr/share/fonts/dejavu/DejaVuSans.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'].find { |p| File.file?(p) }
    bold = ['/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'].find { |p| File.file?(p) }
    raise 'DejaVu regular/bold missing' unless regular && bold
    pdf = File.join(out, 'runtime.pdf')
    Prawn::Document.generate(pdf) do
      font_families.update('DejaVu' => { normal: regular, bold: bold })
      font('DejaVu') { text 'JRC Conversas — ação e aprovação', size: 22; text 'Runtime OCR TEST 12345', style: :bold, size: 32 }
    end
    text = command!('pdftotext', pdf, '-')
    raise 'Unicode PDF extraction failed' unless text.include?('ação e aprovação')
    fonts = command!('pdffonts', pdf)
    raise 'DejaVu not embedded' unless fonts.include?('DejaVuSans') && fonts.include?('DejaVuSans-Bold')
    report[:checks] << 'pdf_dejavu_regular_bold_unicode'
    prefix = File.join(out, 'runtime-page')
    command!('pdftoppm', '-r', '180', '-f', '1', '-singlefile', '-png', pdf, prefix)
    languages = command!('tesseract', '--list-langs')
    raise 'OCR language data missing' unless languages.lines.map(&:strip).include?('por') && languages.lines.map(&:strip).include?('eng')
    ocr = command!('tesseract', prefix + '.png', 'stdout', '-l', 'por+eng', '--psm', '6')
    raise 'Real OCR extraction failed' unless ocr.include?('12345')
    File.write(File.join(out, 'ocr.txt'), ocr)
    report[:checks] << 'poppler_rasterization_and_tesseract_por_eng'
    require 'caxlsx'
    require 'zip'
    xlsx = File.join(out, 'runtime.xlsx')
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: 'Runtime') { |s| s.add_row ['Aprovação', 12.34] }
    package.serialize(xlsx)
    Zip::File.open(xlsx) do |zip|
      raise 'XLSX content missing' unless zip.read('xl/worksheets/sheet1.xml').include?('12.34')
      raise 'XLSX metadata missing' unless zip.find_entry('[Content_Types].xml')
    end
    report[:checks] << 'real_xlsx'
    root = '/app/public/vite'
    manifest = [root + '/.vite/manifest.json', root + '/manifest.json'].find { |p| File.file?(p) }
    raise 'Compiled manifest missing' unless manifest
    entries = JSON.parse(File.read(manifest))
    selected = []
    ['entrypoints/dashboard.js', 'entrypoints/v3app.js'].each do |key|
      entry = entries.fetch(key)
      raise 'Entrypoint is not compiled' unless entry['isEntry'] == true
      selected << entry.fetch('file')
    end
    css = entries.values.flat_map { |v| v['css'] || [] }.uniq
    raise 'Compiled CSS missing' if css.empty?
    selected << css.first
    all_files = (entries.values.map { |v| v['file'] } + css).compact.uniq
    inventory = all_files.map do |file|
      path = File.expand_path(file, root)
      raise 'Asset escaped output' unless path.start_with?(root + '/') && File.file?(path) && File.size(path).positive?
      { file: file, bytes: File.size(path), sha256: Digest::SHA256.file(path).hexdigest }
    end
    File.write(File.join(out, 'assets.json'), JSON.pretty_generate({ manifest_sha256: Digest::SHA256.file(manifest).hexdigest,
      files: inventory, required_http: selected.uniq.map { |p| inventory.find { |i| i[:file] == p } } }))
    report[:checks] << 'new_dashboard_v3app_css_manifest'
  when 'enqueue'
    require '/smoke/worker'
    ActiveRecord::Base.connection.execute('CREATE TABLE jrc_runtime_smoke_receipts (nonce varchar PRIMARY KEY, details jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now())')
    report[:jid] = RuntimeBuildProbe.perform_async(nonce)
    raise 'Sidekiq enqueue failed' unless report[:jid].is_a?(String)
    report[:checks] << 'persisted_sidekiq_enqueue'
  when 'verify_worker'
    redis = Redis.new(url: ENV.fetch('REDIS_URL'))
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
    receipt = nil
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      receipt = redis.get('jrc:runtime:receipt:' + nonce)
      break if receipt
      sleep 0.5
    end
    raise 'Sidekiq receipt missing' unless receipt
    data = JSON.parse(receipt)
    raise 'Wrong worker source' unless data.fetch('product_sha') == ENV.fetch('RUNTIME_PRODUCT_SHA') && data.fetch('pid') > 1
    persisted = ActiveRecord::Base.connection.select_value("SELECT details->>'product_sha' FROM jrc_runtime_smoke_receipts WHERE nonce=" + ActiveRecord::Base.connection.quote(nonce))
    raise 'Real database persistence missing' unless persisted == ENV.fetch('RUNTIME_PRODUCT_SHA')
    report[:checks] << 'real_sidekiq_process_redis_postgresql_persistence'
  else
    raise 'Unknown probe phase'
  end
  report[:passed] = true
rescue StandardError => e
  report[:failure] = { class: e.class.name, message: e.message.to_s[0, 240] }
  raise
ensure
  File.write(File.join(out, 'probe-' + ARGV.fetch(0) + '.json'), JSON.pretty_generate(report))
  puts JSON.generate(report)
end
