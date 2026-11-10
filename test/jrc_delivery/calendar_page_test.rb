require 'minitest/autorun'
require 'time'

module JrcCrm; end
require_relative '../../app/services/jrc_crm/calendar_page'

# In-memory relation double: validates selection/pagination and strict parsing.
# Does not claim to validate ActiveRecord SQL, PostgreSQL or HTTP authorization.
class CalendarPageTest < Minitest::Test
  Row = Struct.new(:id, :due_at, :account_id)

  class Zone
    def name = 'America/Sao_Paulo'
    def local(year, month, day) = Time.new(year, month, day, 0, 0, 0, '-03:00')
  end

  class Relation
    attr_reader :records
    def initialize(records) = @records = records
    def where(due_at:) = self.class.new(records.select { |row| due_at.cover?(row.due_at) })
    def distinct = self.class.new(records.uniq(&:id))
    def unscope(*) = self
    def count(*) = records.length
    def reorder(*) = self.class.new(records.sort_by { |row| [row.due_at, row.id] })
    def offset(value) = self.class.new(records.drop(value))
    def limit(value) = self.class.new(records.take(value))
    def includes(*) = self
  end

  def setup
    @params = { starts_on: '2026-11-01', ends_before: '2026-12-01' }
    @rows = (1..61).map { |i| Row.new(i, Time.iso8601('2026-11-07T12:00:00-03:00'), 1) }.reverse
    @scope = Relation.new(@rows)
  end

  def query(params = {}, scope: @scope, **keywords)
    JrcCrm::CalendarPage.new(scope: scope, params: @params.merge(params).merge(keywords), zone: Zone.new)
  end

  def test_default_page_is_bounded_and_stably_ordered
    result = query.call
    assert_equal (1..25).to_a, result[:records].records.map(&:id)
    assert_equal({ page: 1, per_page: 25, pages: 3, total: 61, starts_on: '2026-11-01', ends_before: '2026-12-01',
                   time_zone: 'America/Sao_Paulo' }, result[:meta])
  end

  def test_pages_cover_rows_once_without_changing_the_source
    pages = (1..3).map { |page| query(page: page).call[:records].records }
    assert_equal [25, 25, 11], pages.map(&:size)
    assert_equal (1..61).to_a, pages.flatten.map(&:id)
    assert_equal 61, @scope.records.size
    assert_equal 61, @scope.records.first.id
  end

  def test_clamps_a_page_after_filtered_results_shrink
    result = query({ page: '99' }, scope: Relation.new([@rows.first])).call
    assert_equal 1, result[:meta][:page]
    assert_equal 1, result[:meta][:total]
  end

  def test_empty_scope_has_no_synthetic_records
    result = query({ page: 9 }, scope: Relation.new([])).call
    assert_equal 1, result[:meta][:pages]
    assert_equal 0, result[:meta][:total]
    assert_empty result[:records].records
  end

  def test_local_date_boundaries_are_half_open
    times = %w[2026-11-01T02:59:59Z 2026-11-01T03:00:00Z 2026-12-01T02:59:59Z 2026-12-01T03:00:00Z]
    rows = times.each_with_index.map { |time, i| Row.new(i + 1, Time.iso8601(time), 1) }
    result = query({}, scope: Relation.new(rows)).call
    assert_equal [2, 3], result[:records].records.map(&:id)
  end

  def test_distinct_does_not_duplicate_joined_rows
    result = query({}, scope: Relation.new([@rows.first, @rows.first])).call
    assert_equal 1, result[:meta][:total]
    assert_equal 1, result[:records].records.size
  end

  def test_requested_page_size_is_honored
    result = query(page: '2', per_page: '10').call
    assert_equal (11..20).to_a, result[:records].records.map(&:id)
    assert_equal 7, result[:meta][:pages]
  end

  def test_leap_day_and_full_leap_year_are_valid
    assert query(starts_on: '2028-02-29', ends_before: '2028-03-01')
    assert query(starts_on: '2028-01-01', ends_before: '2029-01-01')
  end

  [false, true, [], {}, 0, -1, 1.5, '1.5', '1oops', '1e3', '', ' 1', '0', 1_000_001].each_with_index do |value, index|
    define_method("test_rejects_invalid_page_#{index}") do
      assert_raises(JrcCrm::CalendarPage::InvalidQuery) { query(page: value) }
    end
  end

  [0, 101, '999', false, [], {}].each_with_index do |value, index|
    define_method("test_rejects_invalid_size_#{index}") do
      assert_raises(JrcCrm::CalendarPage::InvalidQuery) { query(per_page: value) }
    end
  end

  [nil, false, [], {}, '2026-02-29', '2026-11-31', '2026-1-01', '2026-11-01T00:00:00Z', '0000-11-01'].each_with_index do |value, index|
    define_method("test_rejects_invalid_start_#{index}") do
      assert_raises(JrcCrm::CalendarPage::InvalidQuery) { query(starts_on: value) }
    end
  end

  def test_rejects_missing_end_and_nonpositive_or_oversized_window
    [nil, '2026-10-31', '2026-11-01', '2027-11-03'].each do |value|
      assert_raises(JrcCrm::CalendarPage::InvalidQuery) { query(ends_before: value) }
    end
  end
end
