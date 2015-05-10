class Device < ActiveRecord::Base
  belongs_to :user

  enum device_type: { ios: 0, browser_safari: 1 }
end
