class CreateRemoteFiles < ActiveRecord::Migration[7.0]
  def change
    create_table :remote_files do |t|
      t.uuid :fingerprint, null: false, index: {unique: true}
      t.text :original_url, null: false
      t.text :storage_url, null: false
      t.jsonb :data, default: {}
      t.jsonb :settings, default: {}
      t.timestamps
    end
  end
end
