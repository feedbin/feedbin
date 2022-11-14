module Search
  class BulkRecord
    def initialize(action:, index:, id:, document:)
      @action = action
      @index = index
      @id = id
      @document = document
    end

    def to_request
      parts = [{
        @action => {
          "_index" => @index,
          "_id" => @id
        }
      }]
      parts.push(@document) unless @document.nil?
      parts.map { JSON.dump(_1) }.join("\n")
    end
  end
end
