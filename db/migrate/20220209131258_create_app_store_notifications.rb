class CreateAppStoreNotifications < ActiveRecord::Migration[7.0]
  def change
    create_table :app_store_notifications do |t|
      t.references :user,                    null: false, index: true
      t.text       :original_transaction_id, null: false, index: true
      t.uuid       :notification_id,         null: false, index: {unique: true}
      t.text       :notification_type,       null: false
      t.text       :subtype,                 null: true
      t.text       :version,                 null: false
      t.datetime   :processed_at,            null: true
      t.datetime   :created_at,              null: false
      t.datetime   :updated_at,              null: false
      t.jsonb      :data,                    null: false
    end
  end
end
