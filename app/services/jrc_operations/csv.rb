module JrcOperations
  class Csv
    def self.safe(value)
      string = value.to_s
      string.match?(/\A[\s]*[=+@\-]/) ? "'#{string}" : string
    end
  end
end
