class CreateNewsletterSenders < ActiveRecord::Migration[6.0]
  def change
    create_table :newsletter_senders do |t|
      t.references :feed, foreign_key: true, null: false, index: {unique: true}
      t.boolean :active, null: false, default: true
      t.text :token, null: false, index: true
      t.text :full_token, null: false
      t.text :email, null: false
      t.text :name

      t.timestamps
    end
  end
end
