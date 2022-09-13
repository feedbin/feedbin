class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

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

end
