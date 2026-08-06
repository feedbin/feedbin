require "test_helper"

class EntryPresenterXssTest < ActionView::TestCase
  setup do
    @feed = feeds(:daring_fireball)
  end

  def presenter_for(entry)
    EntryPresenter.new(entry, nil, view)
  end

  def entry_with(attributes)
    @feed.entries.create!({
      title: "Episode 1",
      url: "http://example.com/episode-1",
      public_id: SecureRandom.hex,
      entry_id: SecureRandom.hex
    }.merge(attributes))
  end

  # 168 — nothing on this path validates the scheme, and the value is copied
  # verbatim out of a podcast feed's <enclosure url>.
  test "enclosure_url refuses a scheme that is not http or https" do
    [
      "javascript:alert(document.domain)",
      "javascript://comment%0Aalert(document.domain)",
      "JaVaScRiPt://%0Aalert(document.domain)",
      "data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg=="
    ].each do |payload|
      entry = entry_with(data: {"enclosure_url" => payload, "enclosure_type" => "audio/mpeg"})
      presenter = presenter_for(entry)

      assert_nil presenter.enclosure_url, "expected #{payload.inspect} to be refused"
      refute presenter.has_enclosure?, "the whole audio block should drop for #{payload.inspect}"
    end
  end

  test "enclosure_url keeps ordinary media urls" do
    entry = entry_with(data: {"enclosure_url" => "http://example.com/ep1.mp3", "enclosure_type" => "audio/mpeg"})
    presenter = presenter_for(entry)

    assert_equal "http://example.com/ep1.mp3", presenter.enclosure_url
    assert presenter.has_enclosure?
  end

  test "enclosure_url still resolves a relative url against the entry" do
    entry = entry_with(data: {"enclosure_url" => "/ep1.mp3", "enclosure_type" => "audio/mpeg"})

    assert_equal "http://example.com/ep1.mp3", presenter_for(entry).enclosure_url
  end

  # 169 — the method returns markup when the title is blank, and two templates
  # put the result in a title= attribute.
  test "entry_view_title_text is plain text even when the entry has no title" do
    entry = entry_with(title: nil)
    presenter = presenter_for(entry)

    text = presenter.entry_view_title_text

    assert_equal @feed.title, text
    refute_includes text, "<"
    refute_includes text, ">"
  end

  test "entry_view_title still carries the user_title hook for element content" do
    entry = entry_with(title: nil)

    markup = presenter_for(entry).entry_view_title

    assert_includes markup, %(data-behavior="user_title")
    assert_includes markup, @feed.title
  end

  test "entry_view_title_text is the title when there is one" do
    entry = entry_with(title: "Episode 1")

    assert_equal "Episode 1", presenter_for(entry).entry_view_title_text
  end
end
