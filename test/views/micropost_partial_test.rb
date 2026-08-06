require "test_helper"

class MicropostPartialTest < ActionView::TestCase
  setup do
    @feed = Feed.create!(feed_url: SecureRandom.hex, title: "micro.blog")
  end

  test "renders a micropost whose author has no avatar" do
    entry = micropost_entry("name" => "Someone", "url" => "https://micro.blog/someone",
      "_microblog" => {"username" => "someone"})

    html = render_micropost(entry)

    assert_includes html, "favicon-profile-default"
    assert_includes html, "Someone"
  end

  test "renders a micropost whose author has an avatar" do
    entry = micropost_entry("name" => "Someone", "url" => "https://micro.blog/someone",
      "avatar" => "https://micro.blog/someone/avatar.jpg",
      "_microblog" => {"username" => "someone"})

    html = render_micropost(entry)

    assert_includes html, RemoteFile.signed_url("https://micro.blog/someone/avatar.jpg")
  end

  test "renders a micropost with no timestamp" do
    entry = micropost_entry("name" => "Someone", "url" => "https://micro.blog/someone",
      "_microblog" => {"username" => "someone"})

    html = render_micropost(entry, published: nil)

    assert_not_includes html, "<time"
  end

  private

  def micropost_entry(author)
    @feed.entries.create!(
      title: nil,
      url: "https://micro.blog/someone/1",
      content: "<p>hi</p>",
      public_id: SecureRandom.hex,
      entry_id: SecureRandom.hex,
      published: Time.now,
      data: {"author" => author}
    )
  end

  # The partial serves both the entry body, where the local is an Entry, and the
  # replies dialog, where it is the OpenStruct MicropostsController builds.
  def render_micropost(entry, published: :entry)
    local = if published == :entry
      entry
    else
      OpenStruct.new(micropost: entry.micropost, fully_qualified_url: entry.url,
        published: published, content: entry.content, id: entry.entry_id, media: [])
    end
    ApplicationController.render(partial: "entries/micropost", locals: {micropost: local}, formats: :html)
  end
end
