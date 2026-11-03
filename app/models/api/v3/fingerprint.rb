module Api
  module V3
    # A fingerprint of the set of rows in a relation: the row count and a sum
    # of per-row hashes of some columns, as "count.sum". Order doesn't matter,
    # so adding or removing any row moves it, and unlike count and newest id,
    # a removal and an insert cannot net out. Postgres answers it from an
    # index on the columns.
    module Fingerprint
      def self.of(scope, *columns)
        row = columns.map { scope.connection.quote_column_name(_1) }.join(", ")
        scope.reorder(nil).pick(Arel.sql("count(*)"), Arel.sql("coalesce(sum(hashtext(concat_ws(':', #{row}))), 0)")).join(".")
      end
    end
  end
end
