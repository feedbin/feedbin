require "test_helper"

class JsonConverterTest < ActiveSupport::TestCase
  test "dump parses a JSON string into a Ruby object" do
    assert_equal({"a" => 1}, JsonConverter.dump('{"a":1}'))
  end

  test "dump returns the value unchanged when not a string" do
    hash = {"a" => 1}
    assert_same hash, JsonConverter.dump(hash)
  end

  test "load parses a JSON string into a Ruby object" do
    assert_equal([1, 2], JsonConverter.load("[1,2]"))
  end

  test "load returns the value unchanged when not a string" do
    array = [1, 2]
    assert_same array, JsonConverter.load(array)
  end
end
