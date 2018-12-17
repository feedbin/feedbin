class CreateSubscriptions < ActiveRecord::Migration[4.2]
  def change
    create_table :subscriptions do |t|
      t.integer :user_id
      t.integer :feed_id

      t.timestamps
    end

    add_index :subscriptions, :user_id
    add_index :subscriptions, :feed_id
    add_index :subscriptions, [:user_id, :feed_id], unique: true
  end
end
