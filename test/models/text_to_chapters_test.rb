require "test_helper"

class TextToChaptersTest < ActiveSupport::TestCase
  test "returns an empty array when no chapter block is found" do
    assert_equal [], TextToChapters.call("just some text", 600)
    assert_equal [], TextToChapters.call("", 600)
  end

  test "requires at least two consecutive timestamp lines" do
    assert_equal [], TextToChapters.call("00:00 Intro\n", 600)
  end

  test "parses minutes:seconds timestamps" do
    text = "00:00 Intro\n01:30 Topic A\n03:00 Topic B"
    chapters = TextToChapters.call(text, 600)

    assert_equal 3, chapters.size
    assert_equal({seconds: 0,   timestamp: "00:00", title: "Intro",   duration: 90}, chapters[0])
    assert_equal({seconds: 90,  timestamp: "01:30", title: "Topic A", duration: 90}, chapters[1])
    assert_equal({seconds: 180, timestamp: "03:00", title: "Topic B", duration: 420}, chapters[2])
  end

  test "parses hours:minutes:seconds timestamps" do
    text = "00:00 Start\n1:00:00 Hour two"
    chapters = TextToChapters.call(text, nil)

    assert_equal 0,    chapters[0][:seconds]
    assert_equal 3600, chapters[1][:seconds]
  end

  test "last chapter duration is nil when total_duration is nil" do
    text = "00:00 a\n01:00 b"
    chapters = TextToChapters.call(text, nil)
    assert_nil chapters.last[:duration]
  end

  test "strips whitespace from chapter titles" do
    text = "00:00   Intro  \n01:00   Topic  "
    chapters = TextToChapters.call(text, 120)
    assert_equal "Intro", chapters[0][:title]
    assert_equal "Topic", chapters[1][:title]
  end
end
