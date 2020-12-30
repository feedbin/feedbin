class CreateEmbeds < ActiveRecord::Migration[6.0]
  def change
    create_table :embeds do |t|
      t.text :provider_id, null: false
      t.references :parent, type: :text
      t.integer :source, null: false
      t.jsonb :data, null: false

      t.timestamps
    end
    add_index :embeds, [:source, :provider_id], unique: true
  end
end
