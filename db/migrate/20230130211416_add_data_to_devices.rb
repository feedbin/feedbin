class AddDataToDevices < ActiveRecord::Migration[7.0]
  def change
    add_column :devices, :data, :jsonb, default: {}
  end
end
