class CreateAuthenticationTokens < ActiveRecord::Migration[6.0]
  def change
    create_table :authentication_tokens do |t|
      t.references :user, foreign_key: true, null: false
      t.text :token, null: false
      t.integer :purpose, null: false
      t.jsonb :data, default: {}
      t.timestamps
    end
    add_index :authentication_tokens, [:purpose, :token], unique: true
  end
end
