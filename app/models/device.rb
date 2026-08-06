class Device < ApplicationRecord
  belongs_to :user

  enum :device_type, {notifier: 0, safari: 1, podcast: 2, browser: 3}

  # index_devices_on_lower_tokens covers lower(token) alone, with no user_id,
  # so a token identifies one physical device rather than one device per
  # account. Look it up globally — two accounts signed in to the same browser
  # profile share a push endpoint — so a device that moves accounts follows
  # the account instead of colliding with the index.
  def self.register(user, token, attributes)
    device = where_lower(token: token).take || new
    device.assign_attributes(attributes)
    device.user = user
    device.save
    device
  rescue ActiveRecord::RecordNotUnique
    # A concurrent registration of the same token inserted the row first.
    where_lower(token: token).take&.tap do |winner|
      winner.assign_attributes(attributes)
      winner.user = user
      winner.save
    end
  end
end
