class CreateDevices < ActiveRecord::Migration[4.2]
  def change
    create_table :devices do |t|
      t.belongs_to :user, index: true
      t.text :token
      t.text :model
      t.integer :device_type

      t.timestamps
    end
    add_index :devices, :token
  end
end
