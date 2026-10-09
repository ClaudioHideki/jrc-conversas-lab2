# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDeskConcurrency do
  let(:guard) { Object.new.extend(JrcServiceDeskConcurrency) }

  it 'allows each exact disposable name only when the actual PostgreSQL test connection matches' do
    JrcServiceDeskConcurrency::DISPOSABLE_DATABASES.each do |database|
      with_modified_env(JRC_SD_CONCURRENCY: '1', POSTGRES_DATABASE: database) do
        config = instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, database: database)
        allow(ActiveRecord::Base).to receive(:connection_db_config).and_return(config)
        expect(guard.service_desk_concurrency_enabled?).to be(true)
      end
    end
  end

  it 'rejects opt-out, unlisted names, connection mismatch and a production environment' do
    database = 'jrc_rel_sd_r345_concurrency_test'
    with_modified_env(JRC_SD_CONCURRENCY: '0', POSTGRES_DATABASE: database) do
      expect(guard.service_desk_concurrency_enabled?).to be(false)
    end
    with_modified_env(JRC_SD_CONCURRENCY: '1', POSTGRES_DATABASE: "#{database}_other") do
      expect(guard.service_desk_concurrency_enabled?).to be(false)
    end
    with_modified_env(JRC_SD_CONCURRENCY: '1', POSTGRES_DATABASE: database) do
      config = instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, database: 'original_application_db')
      allow(ActiveRecord::Base).to receive(:connection_db_config).and_return(config)
      expect(guard.service_desk_concurrency_enabled?).to be(false)
      matching_config = instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, database: database)
      allow(ActiveRecord::Base).to receive(:connection_db_config).and_return(matching_config)
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      expect(guard.service_desk_concurrency_enabled?).to be(false)
    end
  end

  it 'rejects a non-PostgreSQL adapter even when the disposable database and opt-in match' do
    database = 'jrc_rel_sd_r345_concurrency_test'
    adapter = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter, adapter_name: 'SQLite')
    config = instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, database: database)
    with_modified_env(JRC_SD_CONCURRENCY: '1', POSTGRES_DATABASE: database) do
      allow(ActiveRecord::Base).to receive(:connection).and_return(adapter)
      allow(ActiveRecord::Base).to receive(:connection_db_config).and_return(config)
      expect(guard.service_desk_concurrency_enabled?).to be(false)
    end
  end
end
