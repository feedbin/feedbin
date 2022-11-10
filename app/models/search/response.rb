module Search
  class Response
    def initialize(data, page: 1, per_page: WillPaginate.per_page)
      @data     = data
      @page     = page
      @per_page = per_page
    end

    def total
      @data.dig("hits", "total", "value") || 0
    end

    def ids
      @data.dig("hits", "hits")&.map {|hit| hit["_id"].to_i } || []
    end

    def records(klass)
      klass.in_order_of(:id, ids)
    end

    def pagination
      Array.new(total).paginate(page: @page, per_page: @per_page)
    end

    def error?
      @data.key?("error")
    end
  end
end