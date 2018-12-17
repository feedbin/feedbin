class CreateSupportedSharingServices < ActiveRecord::Migration[4.2]
  def change
    create_table :supported_sharing_services do |t|
      t.belongs_to :user, index: true, null: false
      t.string :service_id, null: false
      t.hstore :settings
      t.json :service_options

      t.timestamps
    end
    add_index :supported_sharing_services, [:user_id, :service_id], unique: true
  end
end
