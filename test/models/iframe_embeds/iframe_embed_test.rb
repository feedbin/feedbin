require 'test_helper'

class IframeEmbedTest < ActiveSupport::TestCase

  test "should return youtube handler" do
    url = "https://youtu.be/1234"

    klass = IframeEmbed.fetch(url)
    assert_instance_of IframeEmbed::Youtube, klass
  end

  test "should return default handler" do
    url = "https://myembedservice.com/1234"

    klass = IframeEmbed.fetch(url)
    assert_instance_of IframeEmbed::Default, klass
  end

end