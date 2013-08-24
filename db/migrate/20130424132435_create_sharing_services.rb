class CreateSharingServices < ActiveRecord::Migration
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
