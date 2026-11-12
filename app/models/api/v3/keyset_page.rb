module Api
  module V3
    # Cursor: {sort:, <key>:, id:}, the key an integer (microseconds for a time).
    class KeysetPage
      def initialize(scope, sort:, column:, direction:, limit:, cursor: nil, tiebreak: :id, key: "key")
        @scope = scope
        @sort = sort
        @column = column
        @direction = direction
        @limit = limit
        @cursor = cursor
        @tiebreak = tiebreak
        @key = key
      end

      # Fetches limit + 1 rows to tell whether another page follows.
      def relation
        page_of(after_cursor(@scope))
      end

      def records
        load.first
      end

      def more?
        load.last
      end

      def next_cursor
        cursor_at(records.last) if more?
      end

      def cursor_at(record)
        Cursor.encode(:sort => @sort, @key => encode(record.public_send(@column)), :id => record.public_send(@tiebreak))
      end

      private

      def load
        @load ||= begin
          rows = fetch
          more = rows.size > @limit
          rows.pop if more
          [rows, more]
        end
      end

      def fetch
        relation.to_a
      end

      def after_cursor(scope)
        return scope unless (after = position)
        connection = scope.connection
        table = connection.quote_table_name(scope.model.table_name)
        column, tiebreak = [@column, @tiebreak].map { connection.quote_column_name(_1) }
        operator = (@direction == :asc) ? ">" : "<"
        scope.where("(#{table}.#{column}, #{table}.#{tiebreak}) #{operator} (?, ?)", *after)
      end

      def page_of(scope)
        scope.reorder(@column => @direction, @tiebreak => @direction).limit(@limit + 1)
      end

      def position
        return nil unless @cursor
        value, id = @cursor.values_at(@key, "id")
        raise Cursor::Invalid unless @cursor["sort"] == @sort && value.is_a?(Integer) && id.is_a?(Integer)
        [decode(value), id]
      end

      def integer_column?
        %i[integer big_integer].include?(@scope.model.type_for_attribute(@column.to_s).type)
      end

      def encode(value)
        integer_column? ? value.to_i : (value.to_r * 1_000_000).to_i
      end

      def decode(value)
        integer_column? ? value : Time.at(Rational(value, 1_000_000)).utc
      end
    end
  end
end
