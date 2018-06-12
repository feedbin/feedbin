class AddApplicationAndOperatingSystemToDevices < ActiveRecord::Migration[4.2]
  def change
    add_column :devices, :application, :text
    add_column :devices, :operating_system, :text
  end
end
