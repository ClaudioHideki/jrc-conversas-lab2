require 'minitest/autorun'
require 'stringio'
require_relative 'candidate_fixture_scanner'

class CandidateFixtureScannerTest < Minitest::Test
  def test_only_exact_synthetic_bytes_are_accepted
    bytes = 'known synthetic fixture'
    stream = StringIO.new("zINSTREAM\0" + [bytes.bytesize].pack('N') + bytes + [0].pack('N'))
    assert_equal "stream: OK\0", CandidateFixtureScanner.reply(stream, [Digest::SHA256.hexdigest(bytes)])
  end

  def test_unknown_content_is_never_accepted
    bytes = 'another document'
    stream = StringIO.new("zINSTREAM\0" + [bytes.bytesize].pack('N') + bytes + [0].pack('N'))
    assert_includes CandidateFixtureScanner.reply(stream, [Digest::SHA256.hexdigest('known')]), 'FOUND'
  end

  def test_malformed_and_truncated_streams_fail_closed
    ["nPING\0", "zINSTREAM\0\0", "zINSTREAM\0" + [8].pack('N') + 'short'].each do |bytes|
      assert_equal "stream: ERROR\0", CandidateFixtureScanner.reply(StringIO.new(bytes), [])
    end
  end

  def test_oversized_chunk_is_not_read_or_accepted
    assert_equal "stream: ERROR\0", CandidateFixtureScanner.reply(StringIO.new("zINSTREAM\0" + [65_537].pack('N')), [])
  end
end
