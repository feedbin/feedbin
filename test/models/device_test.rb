require 'test_helper'

class DeviceTest < ActiveSupport::TestCase
  setup do
    user = users(:ben)
    @device = user.devices.build(
      token: 'token',
      model: 'model',
      device_type: Device.device_types[:ios],
      application: 'application',
      operating_system: 'iOS 10',
    )
  end

  test "should have types" do
    assert @device.valid?
  end
end

# class Device < ActiveRecord::Base
#   belongs_to :user
#
#   enum device_type: { ios: 0, safari: 1 }
# end
