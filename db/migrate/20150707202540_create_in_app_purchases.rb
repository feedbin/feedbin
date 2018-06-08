class CreateInAppPurchases < ActiveRecord::Migration[4.2]
  def change
    create_table :in_app_purchases do |t|
      t.belongs_to :user, index: true
      t.text :transaction_id
      t.datetime :purchase_date
      t.json :receipt
      t.timestamps
    end
    add_index :in_app_purchases, :transaction_id, unique: true
  end
end
