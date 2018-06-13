class CreateDeletedUsers < ActiveRecord::Migration[4.2]
  def change
    create_table :deleted_users do |t|
      t.text :email
      t.text :customer_id

      t.timestamps
    end
    add_index :deleted_users, :email
  end
end
