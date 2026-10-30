require "test_helper"

class Api::V3::CursorTest < ActiveSupport::TestCase
  test "round trips fields" do
    cursor = Api::V3::Cursor.encode(timestamp: 1787130751123456, id: 2947218)

    assert_equal "7b2274696d657374616d70223a313738373133303735313132333435362c226964223a323934373231387d", cursor
    assert_equal({"timestamp" => 1787130751123456, "id" => 2947218}, Api::V3::Cursor.decode(cursor))
  end

  test "rejects a cursor that does not decode" do
    ["", "zz", "abc", "5b315d", "7b2274", ["7b7d"]].each do |cursor|
      assert_raises(Api::V3::Cursor::Invalid, cursor.inspect) { Api::V3::Cursor.decode(cursor) }
    end
  end
end
