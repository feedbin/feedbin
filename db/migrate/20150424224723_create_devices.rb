class CreateDevices < ActiveRecord::Migration
  def change
    create_table :devices do |t|
      t.belongs_to :user, index: true
      t.text :token

      t.timestamps
    end
    add_index :devices, :token
  end
end
