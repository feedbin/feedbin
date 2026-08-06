require "test_helper"

class SavedSearchTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
  end

  test "first_letter returns downcased first character of name" do
    saved_search = @user.saved_searches.create!(name: "Ruby News", query: "ruby")
    assert_equal "r", saved_search.first_letter
  end

  test "first_letter downcases an already-uppercase letter" do
    saved_search = @user.saved_searches.create!(name: "Zebra", query: "z")
    assert_equal "z", saved_search.first_letter
  end

  test "first_letter returns 'default' when name is blank" do
    saved_search = SavedSearch.new(user: @user, name: "")
    assert_equal "default", saved_search.first_letter
  end

  test "a name is required, since Postgres will reject it anyway" do
    saved_search = SavedSearch.new(user: @user, query: "ruby")

    refute saved_search.valid?
    assert_includes saved_search.errors[:name], "can't be blank"
  end

  test "a query Elasticsearch cannot parse is rejected" do
    create_feeds(@user)
    saved_search = SavedSearch.new(user: @user, name: "unbalanced", query: %("ruby))

    refute saved_search.valid?, "an unclosed quote returns nothing forever if it is allowed to save"
    assert_includes saved_search.errors[:query], "syntax is invalid"
  end

  test "a query Elasticsearch can parse is accepted" do
    create_feeds(@user)
    saved_search = SavedSearch.new(user: @user, name: "balanced", query: %("ruby"))

    assert saved_search.valid?, saved_search.errors.full_messages.to_sentence
  end

  test "sourceable returns a Sourceable describing the search" do
    saved_search = @user.saved_searches.create!(name: "Ruby News", query: "ruby")
    sourceable = saved_search.sourceable

    assert_instance_of Sourceable, sourceable
    assert_equal "savedsearch", sourceable.type
    assert_equal saved_search.id, sourceable.id
    assert_equal "Ruby News", sourceable.title
  end
end
