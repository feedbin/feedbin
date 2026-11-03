module Api
  module V3
    # One page of a relation in keyset order: rows after a cursor's
    # (key, id) position, keyed on one column with a tiebreak column. A
    # cursor is {sort:, <key>:, id:}: the sort it belongs to, the key as an
    # integer (microseconds for a time), and the tiebreak. A cursor for
    # another sort, or with fields that don't parse, is invalid rather than
    # silently restarting.
    class KeysetPage
      # key: the cursor field the column's value goes in.
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

      # The query for the page, with one row more than the limit to tell
      # whether another page follows.
      def relation
        scope = @scope
        if (after = position)
          connection = @scope.connection
          table = connection.quote_table_name(@scope.model.table_name)
          column, tiebreak = [@column, @tiebreak].map { connection.quote_column_name(_1) }
          operator = (@direction == :asc) ? ">" : "<"
          scope = scope.where("(#{table}.#{column}, #{table}.#{tiebreak}) #{operator} (?, ?)", *after)
        end
        scope.reorder(@column => @direction, @tiebreak => @direction).limit(@limit + 1)
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
          rows = relation.to_a
          more = rows.size > @limit
          rows.pop if more
          [rows, more]
        end
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
