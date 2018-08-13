class Device < ApplicationRecord
  belongs_to :user

  enum device_type: {ios: 0, safari: 1}
end
