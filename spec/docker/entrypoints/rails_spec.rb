require 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'pathname'
require 'tmpdir'

# The subject is an executable shell script rather than a Ruby class.
RSpec.describe 'Rails entrypoint' do # rubocop:disable RSpec/DescribeClass
  let(:directory) { Pathname(Dir.mktmpdir('jrc-entrypoint-')) }
  let(:repository) { Pathname(File.expand_path('../../..', __dir__)) }
  let(:settings) do
    { 'PATH' => "#{directory.join('bin')}:#{ENV.fetch('PATH', nil)}", 'POSTGRES_HOST' => nil,
      'POSTGRES_PORT' => nil, 'POSTGRES_USERNAME' => nil, 'DATABASE_URL' => nil, 'PG_PROBE' => directory.join('pg-probe').to_s }
  end
  let(:probe) { "puts JSON.generate(ENV.values_at('POSTGRES_HOST', 'POSTGRES_PORT', 'POSTGRES_USERNAME'))" }

  before do
    directory.join('bin').mkpath
    directory.join('docker/entrypoints/helpers').mkpath
    helper = directory.join('docker/entrypoints/helpers/pg_database_url.rb')
    FileUtils.cp(repository.join('docker/entrypoints/helpers/pg_database_url.rb'), helper)
    helper.chmod(0o600)
    { 'bundle' => 'exit 0', 'rm' => 'exit 0', 'pg_isready' => 'printf "%s\n" "$@" > "$PG_PROBE"' }.each do |name, body|
      stub = directory.join('bin', name)
      stub.write("#!/bin/sh\n#{body}\n")
      stub.chmod(0o700)
    end
  end

  after { FileUtils.remove_entry_secure(directory) }

  it 'uses DATABASE_URL with a non-executable helper and never prints its password' do
    settings['DATABASE_URL'] = 'postgresql://fixture_user:synthetic_password@db.example.test:6543/testdb'
    stdout, stderr, status = Open3.capture3(
      settings, 'sh', repository.join('docker/entrypoints/rails.sh').to_s, 'ruby', '-rjson', '-e', probe, chdir: directory
    )
    expect(status).to be_success
    expect(JSON.parse(stdout.lines.last)).to eq(['db.example.test', '6543', 'fixture_user'])
    expect(directory.join('pg-probe').read.lines.map(&:strip)).to eq(['-h', 'db.example.test', '-p', '6543', '-U', 'fixture_user'])
    expect(stdout + stderr).not_to include('synthetic_password', settings['DATABASE_URL'])
  end

  it 'preserves individual PG settings and supplies the default port without a DATABASE_URL' do
    settings.merge!('POSTGRES_HOST' => 'pg.example.test', 'POSTGRES_USERNAME' => 'pg_user')
    stdout, _stderr, status = Open3.capture3(
      settings, 'sh', repository.join('docker/entrypoints/rails.sh').to_s, 'ruby', '-rjson', '-e', probe, chdir: directory
    )
    expect(status).to be_success
    expect(JSON.parse(stdout.lines.last)).to eq(['pg.example.test', '5432', 'pg_user'])
    expect(directory.join('pg-probe').read.lines.map(&:strip)).to eq(['-h', 'pg.example.test', '-p', '5432', '-U', 'pg_user'])
  end
end
