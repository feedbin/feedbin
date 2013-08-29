class Coupon < ActiveRecord::Base
  belongs_to :user

  before_create :generate_coupon

  def generate_coupon
    begin
      self.coupon_code = SecureRandom.urlsafe_base64
    end while Coupon.exists?(coupon_code: self.coupon_code)
  end

end
