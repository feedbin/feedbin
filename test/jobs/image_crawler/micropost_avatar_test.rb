require "test_helper"

module ImageCrawler
  class MicropostAvatarTest < ActiveSupport::TestCase
    setup do
      flush_redis
      Sidekiq::Worker.clear_all
      @feed = Feed.create!(feed_url: "https://micro.example/feed.json", host: "micro.example")
      Sidekiq::Worker.clear_all
    end

    def post(avatar, url: "https://micro.example/#{SecureRandom.hex(4)}")
      @feed.entries.create!(
        title: nil, url: url, content: "<p>hi</p>", public_id: SecureRandom.hex, entry_id: SecureRandom.hex, published: Time.now,
        data: {"author" => {"name" => "Someone", "url" => "https://micro.example/someone", "avatar" => avatar, "_microblog" => {"username" => "someone"}}}
      ).tap { Sidekiq::Worker.clear_all }
    end

    def avatar_row_for(entry)
      ::Image.provider_entry_icon.find_by(provider_id: entry.id.to_s)
    end

    def find_args
      Pipeline::Find.jobs.map { it["args"].first }
    end

    test "declines a feed that is not a micropost feed" do
      create_entry(@feed)

      assert_equal [0, 0], MicropostAvatar.schedule(@feed)
      assert_empty Pipeline::Find.jobs
    end

    # The feed icon has its own triggers (create, subscribe, a crawl that
    # changes its url, the backfill), so a dead icon is not asked for again
    # on every crawl with new posts.
    test "does not schedule the feed's own icon" do
      post("https://micro.example/a.png")
      @feed.update!(options: {"image" => {"url" => "https://micro.example/logo.png"}})

      MicropostAvatar.schedule(@feed)

      assert_equal 0, find_args.count { it["preset_name"] == "feed_icon" }
    end

    test "groups row-less entries by avatar url and schedules one Find per unknown url" do
      first = post("https://micro.example/a.png")
      second = post("https://micro.example/a.png")
      other = post("https://micro.example/b.png")
      stored = post("https://micro.example/c.png")
      create_image_row(provider: :entry_icon, provider_id: stored.id.to_s, feed_id: @feed.id, kind: :avatar, variant: "200x200")

      assert_equal [0, 2], MicropostAvatar.schedule(@feed)

      jobs = find_args.select { it["preset_name"] == "micropost_avatar" }
      assert_equal ["https://micro.example/a.png", "https://micro.example/b.png"], jobs.map { it["image_urls"].first }.sort
      a = jobs.find { it["image_urls"].first == "https://micro.example/a.png" }
      assert_equal "#{first.public_id}-avatar", a["id"]
      assert_equal ::Image.kinds[:avatar], a["kind"]
      assert_equal ::Image.providers[:entry_icon], a["provider"]
      assert_equal first.id, a["provider_id"]
      assert_equal @feed.id, a["feed_id"]
      assert_equal true, a["critical"]
      assert_nil avatar_row_for(second), "the sibling waits for the callback"
    end

    test "attaches every entry whose url the table already holds, with no Find" do
      existing = create_image_row(
        provider: :remote_file, provider_id: RemoteFile.fingerprint("https://micro.example/a.png"), feed_id: nil, kind: :avatar,
        url: "https://micro.example/a.png", variant: "200x200", data: {"preset" => "icon", "final_url" => "https://micro.example/a.png"}
      )
      first = post("https://micro.example/a.png")
      second = post("https://micro.example/a.png")

      assert_equal [2, 0], MicropostAvatar.schedule(@feed)

      assert_empty Pipeline::Find.jobs
      [first, second].each do |entry|
        row = avatar_row_for(entry)
        assert_equal existing.storage_path, row.storage_path
        assert_equal existing.image_fingerprint, row.image_fingerprint
        assert row.kind_avatar?
        assert_equal @feed.id, row.feed_id
        assert_equal "https://micro.example/a.png", row.url
        assert_equal "micropost_avatar", row.data["preset"]
      end
    end

    test "a row from another preset or variant is not reused" do
      create_image_row(provider: :entry_preview, provider_id: "9", kind: :poster, url: "https://micro.example/a.png", variant: "542x304", data: {"preset" => "primary"})
      post("https://micro.example/a.png")

      assert_equal [0, 1], MicropostAvatar.schedule(@feed)
    end

    test "skips entries with no avatar and makes a relative one absolute" do
      post(nil)
      relative = post("avatar.png", url: "https://micro.example/posts/1")

      assert_equal [0, 1], MicropostAvatar.schedule(@feed)
      assert_equal "https://micro.example/posts/avatar.png", find_args.last["image_urls"].first
      assert_equal "#{relative.public_id}-avatar", find_args.last["id"]
    end

    # A scheme-less host is a path to a browser and a host to the heuristic
    # parser: both readings go in, the strict one first.
    test "offers both readings of a scheme-less avatar url" do
      post("avatars.example.net/a.png", url: "https://micro.example/posts/1")

      MicropostAvatar.schedule(@feed)

      assert_equal ["https://micro.example/posts/avatars.example.net/a.png", "http://avatars.example.net/a.png"], find_args.last["image_urls"]
    end

    test "passes the proxy's cached object as the second candidate" do
      url = "https://micro.example/a.png"
      RemoteFile.create!(fingerprint: RemoteFile.fingerprint(url), original_url: url, storage_url: "https://icons.example.net/abc/a.png")
      post(url)

      MicropostAvatar.schedule(@feed)

      assert_equal [url, "https://icons.example.net/abc/a.png"], find_args.last["image_urls"]
    end

    test "a backfill schedules off the critical queues" do
      post("https://micro.example/a.png")

      MicropostAvatar.schedule(@feed, critical: false)

      assert_equal false, find_args.last["critical"]
    end

    test "perform with a feed id schedules, and an unknown id does nothing" do
      post("https://micro.example/a.png")

      MicropostAvatar.new.perform(@feed.id)
      assert_equal 1, find_args.count { it["preset_name"] == "micropost_avatar" }
      assert_nothing_raised { MicropostAvatar.new.perform(0) }
    end

    # The callback lands the first entry's row through Upload; the job then
    # attaches every sibling that shares the url, so a feed pass costs one
    # download per distinct avatar.
    test "receive attaches the siblings that share the landed row's url" do
      first = post("https://micro.example/a.png")
      second = post("https://micro.example/a.png")
      third = post("https://micro.example/a.png")
      landed = create_image_row(
        provider: :entry_icon, provider_id: first.id.to_s, feed_id: @feed.id, kind: :avatar,
        url: "https://micro.example/a.png", variant: "200x200", data: {"preset" => "micropost_avatar", "final_url" => "https://micro.example/a.png"}
      )

      MicropostAvatar.new.perform("#{first.public_id}-avatar", {"storage_path" => landed.storage_path, "provider_id" => first.id.to_s})

      [second, third].each do |entry|
        row = avatar_row_for(entry)
        assert_equal landed.storage_path, row.storage_path
        assert_equal "https://micro.example/a.png", row.url
      end
      assert_empty Pipeline::Find.jobs
    end

    # Find writes whichever candidate landed as the row's url. When the
    # legacy object won, the row must still answer to the avatar url the
    # entries carry, or every later lookup misses and downloads again.
    test "receive re-keys a row that landed on the legacy object to the asked url" do
      first = post("https://micro.example/a.png")
      second = post("https://micro.example/a.png")
      landed = create_image_row(
        provider: :entry_icon, provider_id: first.id.to_s, feed_id: @feed.id, kind: :avatar,
        url: "https://icons.example.net/abc/a.png", variant: "200x200", data: {"preset" => "micropost_avatar", "final_url" => "https://icons.example.net/abc/a.png"}
      )
      before = landed.updated_at

      MicropostAvatar.new.perform("#{first.public_id}-avatar", {"storage_path" => landed.storage_path, "provider_id" => first.id.to_s})

      landed.reload
      assert_equal "https://micro.example/a.png", landed.url
      # url_fingerprint is a uuid column: it reads back dashed, while
      # url_fingerprint_for computes bare hex, so same_fingerprint? is the
      # comparison that actually holds (see Image's own note on this).
      assert ::Image.same_fingerprint?(::Image.url_fingerprint_for("https://micro.example/a.png", "200x200"), landed.url_fingerprint)
      assert_equal before, landed.updated_at
      assert_equal landed.storage_path, avatar_row_for(second).storage_path
      # existing_row returns the newest row sharing this fingerprint, and
      # attaching the sibling above created one; it carries the same
      # storage_path/image_fingerprint as the re-keyed row, which is what
      # a later lookup by the asked url actually needs.
      found = MicropostAvatar.existing_row("https://micro.example/a.png")
      assert_equal landed.storage_path, found.storage_path
      assert_equal landed.image_fingerprint, found.image_fingerprint
    end

    test "attaches to an earlier post's own row for the same url" do
      earlier = post("https://micro.example/a.png")
      row = create_image_row(
        provider: :entry_icon, provider_id: earlier.id.to_s, feed_id: @feed.id, kind: :avatar,
        url: "https://micro.example/a.png", variant: "200x200", data: {"preset" => "micropost_avatar", "final_url" => "https://micro.example/a.png"}
      )
      later = post("https://micro.example/a.png")

      assert_equal [1, 0], MicropostAvatar.schedule(@feed)

      assert_empty Pipeline::Find.jobs
      assert_equal row.storage_path, avatar_row_for(later).storage_path
    end

    # The entry_icon slot is shared with podcast art; a row landed there for
    # some other reason must not be treated as this entry's avatar.
    test "receive skips a row that is not an avatar" do
      first = post("https://micro.example/a.png")
      second = post("https://micro.example/a.png")
      landed = create_image_row(
        provider: :entry_icon, provider_id: first.id.to_s, feed_id: @feed.id, kind: :cover_art,
        url: "https://micro.example/a.png", variant: "200x200", data: {"preset" => "micropost_avatar", "final_url" => "https://micro.example/a.png"}
      )

      assert_nothing_raised do
        MicropostAvatar.new.perform("#{first.public_id}-avatar", {"storage_path" => landed.storage_path, "provider_id" => first.id.to_s})
      end

      assert_nil avatar_row_for(second)
    end

    test "receive raises on a payload without storage_path" do
      first = post("https://micro.example/a.png")

      assert_raises(KeyError) { MicropostAvatar.new.perform("#{first.public_id}-avatar", {"provider_id" => first.id.to_s}) }
    end

    test "the micropost_avatar preset is png, unified, content addressed, and calls back here" do
      preset = Image.new(preset_name: "micropost_avatar").preset

      assert_equal 200, preset.width
      assert_equal 200, preset.height
      assert_equal :limit_png, preset.crop
      assert_equal "png", preset.format
      assert preset.unified
      assert preset.content_addressed
      assert_not preset.legacy_store
      assert_equal MicropostAvatar, preset.job_class
    end

    test "pending_entries is an anti-join on the cast entry id" do
      sql = MicropostAvatar.pending_entries(@feed).to_sql

      assert_includes sql, %(LEFT OUTER JOIN "images" ON "images"."provider" = 0 AND "images"."provider_id" = CAST("entries"."id" AS text))
      assert_includes sql, %("images"."id" IS NULL)
      refute_includes sql, "NOT IN"
    end
  end
end
