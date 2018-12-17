class AddCoupons < ActiveRecord::Migration[4.2]
  def change
    create_table :coupons do |t|
      t.references :user, index: true
      t.string :coupon_code
      t.string :sent_to
      t.boolean :redeemed, default: false

      t.timestamps
    end
  end
end
