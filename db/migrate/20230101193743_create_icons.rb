class CreateIcons < ActiveRecord::Migration[7.0]
  def change
    create_table :icons do |t|
      t.bigint :provider, null: false
      t.text :provider_id, null: false
      t.uuid :fingerprint
      t.text :url, null: false

      t.timestamps
    end
    add_index :icons, [:provider_id, :provider], unique: true
  end
end
