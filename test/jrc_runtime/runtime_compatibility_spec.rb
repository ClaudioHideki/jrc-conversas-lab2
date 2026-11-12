# frozen_string_literal: true

abort 'Exclusive disposable runtime database required' unless ENV['JRC_RUNTIME_CANDIDATE'] == '1' &&
                                                           ENV['RAILS_ENV'] == 'test' &&
                                                           ENV['POSTGRES_DATABASE'] == 'jrc_runtime_compatibility_20261112_test' &&
                                                           ENV['POSTGRES_HOST'] == '127.0.0.1' &&
                                                           ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/14'

require_relative '../../spec/rails_helper'
require 'open3'
require 'tmpdir'
require 'timeout'
require 'prawn'
require 'bigdecimal'

RSpec.describe 'Runtime candidate native compatibility', type: :model do
  it 'executes the declared Ruby patchlevel and Node version' do
    expect([RUBY_VERSION, RUBY_PATCHLEVEL]).to eq(['3.4.12', 148])
    out, error, status = Open3.capture3('node', '--version')
    expect(status.success?).to be(true), error
    expect(out.strip).to eq('v24.22.3')
  end

  it 'loads the pinned native libraries without changing the gem versions' do
    require 'grpc'
    require 'pg'
    require 'nokogiri'
    require 'ffi'
    require 'google/protobuf'
    expect(Gem.loaded_specs.values_at('grpc', 'pg', 'nokogiri', 'ffi', 'google-protobuf').map { |s| s.version.to_s })
      .to eq(%w[1.72.0 1.5.3 1.19.4 1.17.2 3.25.7])
    expect(ActiveRecord::Base.connection.select_value('SELECT 1')).to eq(1)
  end

  it 'preserves native decimal arithmetic with the locked BigDecimal' do
    expect(Gem.loaded_specs.fetch('bigdecimal').version.to_s).to eq('3.3.1')
    expect(BigDecimal('0.10') + BigDecimal('0.20')).to eq(BigDecimal('0.30'))
    expect((BigDecimal('1234.56') * BigDecimal('1.05')).round(2).to_s('F')).to eq('1296.29')
  end

  it 'renders regular and bold Unicode PDF text and extracts it with real Poppler' do
    Dir.mktmpdir('jrc-runtime-pdf') do |dir|
      file = File.join(dir, 'runtime.pdf')
      Prawn::Document.generate(file) do |doc|
        doc.font_families.update('Runtime' => {
                                  normal: '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
                                  bold: '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
                                })
        doc.font('Runtime')
        doc.text 'JRC — relatório sintético: ação, São Paulo'
        doc.text 'APROVAÇÃO — R$ 1.234,56', style: :bold
      end
      out, error, status = Open3.capture3('pdftotext', file, '-')
      expect(status.success?).to be(true), error
      expect(out).to include('ação, São Paulo', 'APROVAÇÃO', '1.234,56')
      fonts, error, status = Open3.capture3('pdffonts', file)
      expect(status.success?).to be(true), error
      expect(fonts).to include('DejaVuSans', 'DejaVuSans-Bold')
    end
  end

  it 'rasterizes a synthetic PDF and runs real Tesseract with Portuguese and English data' do
    Dir.mktmpdir('jrc-runtime-ocr') do |dir|
      file = File.join(dir, 'ocr.pdf')
      prefix = File.join(dir, 'ocr')
      Prawn::Document.generate(file) do |doc|
        doc.font('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
        doc.text 'DOCUMENTO SINTETICO JRC 12345', size: 24
      end
      _, error, status = Open3.capture3('pdftoppm', '-r', '150', '-singlefile', '-png', file, prefix)
      expect(status.success?).to be(true), error
      languages, error, status = Open3.capture3('tesseract', '--list-langs')
      expect(status.success?).to be(true), error
      expect(languages.lines.map(&:strip)).to include('por', 'eng')
      out, error, status = Open3.capture3('tesseract', "#{prefix}.png", 'stdout', '-l', 'por+eng', '--psm', '6')
      expect(status.success?).to be(true), error
      expect(out.gsub(/\s+/, ' ')).to include('JRC 12345')
    end
  end

  it 'boots a real Sidekiq process and persists its PostgreSQL/Redis result in disposable services' do
    token = SecureRandom.hex(16)
    queue = 'jrc_runtime_candidate_ci'
    pid = nil
    Dir.mktmpdir('jrc-runtime-sidekiq') do |dir|
      log = File.join(dir, 'worker.log')
      begin
        pid = Process.spawn('bundle', 'exec', 'sidekiq', '-r', './test/jrc_runtime/sidekiq_worker.rb',
                            '-q', queue, '-c', '1', out: log, err: [:child, :out])
        Sidekiq::Testing.disable! do
          Sidekiq::Client.push('class' => 'JrcRuntimeCandidateWorker', 'queue' => queue, 'args' => [token], 'retry' => false)
        end
        result = nil
        Timeout.timeout(60) do
          until result
            result = Sidekiq.redis { |redis| redis.call('GET', "jrc:runtime:#{token}") }
            sleep 0.25 unless result
          end
        end
        expect(JSON.parse(result)).to include('ruby' => '3.4.12', 'database' => 1, 'environment' => 'test',
                                              'database_name' => 'jrc_runtime_compatibility_20261112_test')
      ensure
        if pid && Process.waitpid(pid, Process::WNOHANG).nil?
          Process.kill('TERM', pid)
          begin
            Timeout.timeout(15) { Process.waitpid(pid) }
          rescue Timeout::Error
            Process.kill('KILL', pid)
            Process.waitpid(pid)
          end
        end
        FileUtils.cp(log, File.join(ENV.fetch('RUNNER_TEMP'), 'runtime-sidekiq.log')) if File.file?(log)
      end
    end
  end
end
