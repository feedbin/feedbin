module Api
  module V3
    # "count.sum" of per-row column hashes: a removal plus an insert can't net out,
    # unlike count and max id. Needs an index on the columns to stay cheap.
    module Fingerprint
      def self.of(scope, *columns)
        row = columns.map { scope.connection.quote_column_name(_1) }.join(", ")
        scope.reorder(nil).pick(Arel.sql("count(*)"), Arel.sql("coalesce(sum(hashtext(concat_ws(':', #{row}))), 0)")).join(".")
      end
    end
  end
end
