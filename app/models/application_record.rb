class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  self.attributes_for_inspect = :all

  # data should look like [{model_id => "value"}]
  def self.update_multiple(column:, data:)
    return if data.empty?

    ids = data.keys
    type = columns_hash[column.to_s].sql_type

    condition = Arel::Nodes::Case.new(arel_table[:id])
    data.each do |id, value|
      value = sanitize_sql_for_assignment(["CAST (:value AS #{type})", {value: value}])
      condition.when(id).then(Arel.sql(value))
    end
    where(id: ids).update_all(column => condition)
  end

  def self.where_lower(options = {})
    value = Arel::Nodes::NamedFunction.new("LOWER", [Arel::Nodes.build_quoted(options.values.first)])
    expression = Arel::Nodes::NamedFunction.new("LOWER", [arel_table[options.keys.first]]).eq(value)
    where(expression)
  end

end
