require 'date'

# Opt-in server pagination over an already authorized native Activity relation.
# Does not select a tenant, grant permissions, or change legacy array responses.
class JrcCrm::CalendarPage
  class InvalidQuery < ArgumentError; end

  DEFAULT_PAGE_SIZE = 25
  MAX_PAGE_SIZE = 100
  MAX_WINDOW_DAYS = 366
  MAX_PAGE = 1_000_000

  attr_reader :page, :per_page, :starts_on, :ends_before

  def initialize(scope:, params:, zone: Time.zone)
    @scope = scope
    @zone = zone
    @page = integer!(params[:page], default: 1, maximum: MAX_PAGE)
    @per_page = integer!(params[:per_page], default: DEFAULT_PAGE_SIZE, maximum: MAX_PAGE_SIZE)
    @starts_on = date!(params[:starts_on])
    @ends_before = date!(params[:ends_before])
    unless (@ends_before - @starts_on).between?(1, MAX_WINDOW_DAYS)
      raise InvalidQuery, 'Calendar window must be positive and at most 366 days'
    end
  end

  def call
    rows = windowed_scope.distinct
    total = rows.unscope(:order).count(:id)
    pages = [(total.to_f / per_page).ceil, 1].max
    current = [page, pages].min
    records = rows.reorder(:due_at, :id).offset((current - 1) * per_page).limit(per_page)
                  .includes(:user, :deal, :lead, :contact, :company)
    {
      records: records,
      meta: { page: current, per_page: per_page, pages: pages, total: total,
              starts_on: starts_on.iso8601, ends_before: ends_before.iso8601,
              time_zone: @zone.name }
    }
  end

  # A separate authorized owner list keeps filtering independent of the page.
  # No users without a record in the authorized period are disclosed.
  def owners
    windowed_scope.joins(:user).unscope(:order).distinct
                  .order('users.name', 'users.id').pluck('users.id', 'users.name')
                  .map { |id, name| { id: id, name: name } }
  end

  private

  def windowed_scope
    @scope.where(due_at: boundary(starts_on)...boundary(ends_before))
  end

  def integer!(value, default:, maximum:)
    return default if value.nil?

    valid_type = value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A[1-9]\d{0,6}\z/))
    raise InvalidQuery, 'Calendar page and page size must be positive integers' unless valid_type

    number = value.to_i
    raise InvalidQuery, 'Calendar pagination is out of range' unless number.between?(1, maximum)

    number
  end

  def date!(value)
    raise InvalidQuery, 'Calendar dates must use YYYY-MM-DD' unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    day = Date.iso8601(value)
    raise InvalidQuery, 'Invalid calendar year' unless day.year.positive?

    day
  rescue Date::Error
    raise InvalidQuery, 'Invalid calendar date'
  end

  def boundary(day)
    @zone.local(day.year, day.month, day.day)
  end
end
