class CreateUsers < ActiveRecord::Migration[4.2]
  def change
    create_table :users do |t|
      t.string :email
      t.string :password_digest
      t.string :customer_id
      t.string :last_4_digits
      t.integer :plan_id
      t.text :settings
      t.boolean :admin, default: false
      t.boolean :suspended, default: false

      t.timestamps
    end
  end
end
