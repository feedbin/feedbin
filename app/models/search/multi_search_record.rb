module Search
  class MultiSearchRecord
    def initialize(query:)
      @query = query
    end

    def to_request
      parts = [{}, @query]
      parts.map { JSON.dump(_1) }.join("\n")
    end
  end
end
