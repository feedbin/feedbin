class AddApplicationAndOperatingSystemToDevices < ActiveRecord::Migration
  def change
    add_column :devices, :application, :text
    add_column :devices, :operating_system, :text
  end
end
