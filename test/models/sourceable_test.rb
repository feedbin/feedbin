require "test_helper"

class SourceableTest < ActiveSupport::TestCase
  test "stores attributes and downcases the type" do
    sourceable = Sourceable.new(type: "Feed", id: 42, title: "Daring Fireball")

    assert_equal "feed", sourceable.type
    assert_equal 42, sourceable.id
    assert_equal "Daring Fireball", sourceable.title
    assert_nil sourceable.section
    assert_equal false, sourceable.jumpable
  end

  test "accepts optional section and jumpable" do
    sourceable = Sourceable.new(type: "Tag", id: 1, title: "Tech", section: "Tags", jumpable: true)
    assert_equal "Tags", sourceable.section
    assert_equal true, sourceable.jumpable
  end

  test "to_h returns a hash containing every attribute" do
    sourceable = Sourceable.new(type: "Feed", id: 7, title: "Example", section: "Feeds", jumpable: true)
    hash = sourceable.to_h

    assert_equal({
      title: "Example",
      type: "feed",
      id: 7,
      section: "Feeds",
      jumpable: true
    }, hash)
  end
end
