class AddFixStatusToSubscriptions < ActiveRecord::Migration[7.0]
  def change
    add_column :subscriptions, :fix_status, :bigint
    change_column_default(:subscriptions, :fix_status, from: nil, to: 0)
    UpdateDefaultColumn.perform_async({
      "klass" => Subscription.to_s,
      "column" => "fix_status",
      "default" => 0,
      "schedule" => true
    })
  end
end
