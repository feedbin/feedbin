class TwitterUser < ApplicationRecord
  def user
    @user ||= Twitter::User.new(data.deep_symbolize_keys)
  end

  # nil rather than "": callers fall back with ||, and "" is truthy, so the
  # unconditional to_s turned "we have this user but no avatar" into a value
  # the fallback would not take.
  def profile_image
    user.profile_image_uri_https(:original)&.to_s
  end
end
