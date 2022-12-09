class TwitterUser < ApplicationRecord
  after_commit :save_profile_image, on: [:create, :update]

  def user
    @user ||= Twitter::User.new(data.deep_symbolize_keys)
  end

  def profile_image
    user.profile_image_uri_https(:original).to_s
  end

  def save_profile_image
    ImageCrawler::TwitterProfileImage.perform_async(id)
  end
end


