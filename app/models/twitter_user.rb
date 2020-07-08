class TwitterUser < ApplicationRecord
  def user
    @user ||= Twitter::User.new(data.deep_symbolize_keys)
  end

  def profile_image
    user.profile_image_uri_https("bigger").to_s
  end
end
