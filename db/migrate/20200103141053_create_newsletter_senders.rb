class CreateNewsletterSenders < ActiveRecord::Migration[6.0]
  def change
    create_table :newsletter_senders do |t|
      t.references :feed, foreign_key: true, null: false, index: {unique: true}
      t.text :token, null: false
      t.text :full_token, null: false
      t.text :email, null: false
      t.text :name

      t.timestamps
    end
    add_index :newsletter_senders, :token
  end
end
