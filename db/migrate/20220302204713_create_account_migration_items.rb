class CreateAccountMigrationItems < ActiveRecord::Migration[7.0]
  def change
    create_table :account_migration_items do |t|
      t.references :account_migration, foreign_key: false, null: false
      t.bigint :status, null: false, default: 0
      t.jsonb :data, default: {}
      t.text :message

      t.timestamps
    end
  end
end
