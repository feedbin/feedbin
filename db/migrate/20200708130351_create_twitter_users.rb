class CreateTwitterUsers < ActiveRecord::Migration[6.0]
  def change
    create_table :twitter_users do |t|
      t.text :screen_name, null: false
      t.jsonb :data, null: false

      t.timestamps
    end
    add_index :twitter_users, "lower(screen_name)", unique: true
  end
end
