module JrcProjects
  module Errors
    class DependencyCycle < StandardError; end
    class WipLimit < StandardError; end
  end
end
