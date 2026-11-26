# frozen_string_literal: true

# Alternate Rack entry only for this owned GitHub test server, never port 5379.
require 'webmock'
WebMock.enable!
WebMock.disable_net_connect!(allow_localhost: true)
require File.expand_path('../../../config/environment', __dir__)
require_relative 'owned_public_ending_queue'
require_relative 'owned_recording_media'

SyntheticPublicEndingQueue.install!
SyntheticRecordedCallMedia.install!
run Rails.application
