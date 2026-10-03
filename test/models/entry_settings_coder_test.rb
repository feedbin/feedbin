require "test_helper"

class EntrySettingsCoderTest < ActiveSupport::TestCase
  test "load parses the JSON string form that old rows hold" do
    assert_equal({"embed_duration" => 647}, EntrySettingsCoder.load('{"embed_duration":647}'))
  end

  test "load passes the object form through" do
    hash = {"embed_duration" => 647}
    assert_same hash, EntrySettingsCoder.load(hash)
  end

  test "load returns nil for a blank string, which the store passes for a NULL column" do
    assert_nil EntrySettingsCoder.load("")
  end

  test "load returns nil for nil" do
    assert_nil EntrySettingsCoder.load(nil)
  end

  test "dump writes the JSON string form" do
    assert_equal '{"embed_duration":647}', EntrySettingsCoder.dump({"embed_duration" => 647})
  end

  test "dump drops the keys that nothing reads" do
    dumped = EntrySettingsCoder.dump({
      "newsletter" => "From: News <news@example.com>",
      "media_image" => "https://example.com/a.jpg",
      "newsletter_from" => "News <news@example.com>"
    })

    assert_equal({"newsletter_from" => "News <news@example.com>"}, JSON.parse(dumped))
  end

  test "dump removes NUL characters from string values" do
    dumped = EntrySettingsCoder.dump({"newsletter_from" => "Ne\0ws <news@example.com>", "archived_images" => true})

    assert_equal({"newsletter_from" => "News <news@example.com>", "archived_images" => true}, JSON.parse(dumped))
  end
end
