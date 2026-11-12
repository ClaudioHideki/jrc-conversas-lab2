require 'json'
raise 'Wrong Ruby' unless RUBY_VERSION == '3.4.12' && RUBY_PATCHLEVEL == 148 && RUBY_PLATFORM.include?('musl')
raise 'Wrong Alpine' unless File.read('/etc/alpine-release').start_with?('3.24.')
path = Dir['/tmp/scout-new/gems/scout_apm-5.7.0/lib/allocations.so'].fetch(0)
require path
raise 'Native allocation monitoring disabled' unless ScoutApm::Instruments::Allocations::ENABLED == true
before = ScoutApm::Instruments::Allocations.count
objects = Array.new(2000) { String.new('synthetic JRC') }
after = ScoutApm::Instruments::Allocations.count
raise 'Allocation instrumentation did not execute' unless after - before >= objects.size
File.write('/out/scout-alpine.json', JSON.pretty_generate(passed: true, ruby: RUBY_VERSION,
  patchlevel: RUBY_PATCHLEVEL, platform: RUBY_PLATFORM, alpine: File.read('/etc/alpine-release').strip,
  scout: '5.7.0', allocations_enabled: true, allocations_delta: after - before, application_image_built: false))
