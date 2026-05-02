require "test_helper"

class Search::MultiSearchRecordTest < ActiveSupport::TestCase
  test "to_request emits an empty header line followed by the JSON-dumped query" do
    query = {match: {title: "hi"}}
    record = Search::MultiSearchRecord.new(query: query)
    request = record.to_request

    lines = request.split("\n")
    assert_equal 2, lines.size
    assert_equal({}, JSON.parse(lines.first))
    assert_equal({"match" => {"title" => "hi"}}, JSON.parse(lines.last))
  end
end
