class AddActiveToDevices < ActiveRecord::Migration[7.0]
  def change
    add_column :devices, :active, :bool, default: true
    change_column_null :devices, :user_id, false
    change_column_null :devices, :token, false
    change_column_null :devices, :device_type, false
  end
end
