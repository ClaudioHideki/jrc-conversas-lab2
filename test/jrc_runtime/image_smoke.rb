# frozen_string_literal: true

abort 'Explicit isolated image probe required' unless ENV['JRC_CANDIDATE_IMAGE_SMOKE'] == '1'
require 'bundler/setup'
require 'json'
require 'open3'

abort 'Unexpected Ruby or platform' unless [RUBY_VERSION, RUBY_PATCHLEVEL] == ['3.4.12', 148] && RUBY_PLATFORM.include?('linux-musl')
node, _error, status = Open3.capture3('node', '--version')
abort 'Unexpected Node ABI/runtime' unless status.success? && node.strip == 'v24.22.3'

%w[grpc pg nokogiri ffi google/protobuf scout_apm bigdecimal prawn caxlsx vips].each { |library| require library }
abort 'Wrong native gem versions' unless Gem.loaded_specs.values_at('grpc', 'pg', 'nokogiri', 'ffi', 'google-protobuf', 'scout_apm').map { |gem| gem.version.to_s } ==
                                       %w[1.72.0 1.5.3 1.19.4 1.17.2 3.25.7 5.7.0]
abort 'Decimal mismatch' unless BigDecimal('0.1') + BigDecimal('0.2') == BigDecimal('0.3')
abort 'Native Vips failed' unless Vips::Image.black(2, 2).width == 2
pdf = Prawn::Document.new.tap { |document| document.text 'Synthetic JRC image probe' }.render
abort 'PDF failed' unless pdf.start_with?('%PDF-')
package = Axlsx::Package.new
package.workbook.add_worksheet(name: 'Synthetic') { |sheet| sheet.add_row ['JRC', 1] }
abort 'XLSX failed' unless package.to_stream.string.start_with?('PK')
puts JSON.generate(passed: true, ruby: RUBY_VERSION, ruby_patchlevel: RUBY_PATCHLEVEL, platform: RUBY_PLATFORM,
                   node: node.strip, scout: Gem.loaded_specs.fetch('scout_apm').version.to_s,
                   native_libraries: true, private_data: false, production_services: false, whatsapp_sessions: false)
