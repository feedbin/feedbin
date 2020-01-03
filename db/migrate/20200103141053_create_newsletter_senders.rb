class CreateNewsletterSenders < ActiveRecord::Migration[6.0]
  def change
    create_table :newsletter_senders do |t|
      t.text :token
      t.text :name
      t.text :email

      t.timestamps
    end
  end
end
