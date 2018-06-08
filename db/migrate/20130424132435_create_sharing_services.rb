class CreateSharingServices < ActiveRecord::Migration[4.2]
  def change
    create_table :sharing_services do |t|
      t.references :user
      t.text :label
      t.text :url
      t.timestamps

      t.index :user_id
    end
  end
end
