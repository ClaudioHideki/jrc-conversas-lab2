# frozen_string_literal: true

require 'csv'

# Spreadsheet formula injection protection, shared by the export endpoint/tests.
module JrcServiceDesk::OperationalCsv
  module_function

  def cell(value)
    text = value.nil? ? '' : value.to_s
    text = text.delete("\u0000")
    text.match?(/\A[[:space:]]*[=+@-]/) || text.match?(/\A[\t\r\n]/) ? "'#{text}" : text
  end

  def generate(headers, rows)
    CSV.generate do |csv|
      csv << headers.map { |value| cell(value) }
      rows.each { |row| csv << row.map { |value| cell(value) } }
    end
  end
end
