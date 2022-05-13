class Device < ApplicationRecord
  belongs_to :user

  enum device_type: {notifier: 0, safari: 1, podcast: 2}
end
