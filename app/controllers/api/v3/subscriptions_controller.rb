require "builder"

module Api
  module V3
    # The user's subscriptions: one response with an ETag, ids by default,
    # expand=feed,tags to embed the objects; and the writes: subscribe by
    # URL, search words or feed id; retitle and set preferences; replace the
    # tag set; unsubscribe; export OPML.
    class SubscriptionsController < ApiController
      PREFERENCES = %w[muted media_only show_updates].freeze
      OFFER_LIFETIME = 1.day

      def index
        data = serialize(scope.to_a)
        return if not_modified?(etag_for("subscriptions", digest(data)))
        render_list(data)
      end

      def show
        render json: serialize([subscription]).first
      end

      # Exactly one feed subscribes (201, or 200 when already subscribed);
      # several are a 300 with the candidates; none is a 404. tag_names apply
      # to a new subscription only. A feed_id must be one this endpoint
      # offered the user in a 300, or a feed the user can already read: feed
      # ids are sequential, and Pages, newsletter and secret-URL feeds are
      # ordinary rows.
      def create
        body = request.request_parameters
        unless body.key?("url") ^ body.key?("feed_id")
          raise Problems::InvalidParameter.new("Send url or feed_id, not both.", pointer: "", code: "invalid_value")
        end

        feeds = body.key?("feed_id") ? offered_or_readable(body["feed_id"]) : discover(body["url"].to_s.strip)
        return status_not_found if feeds.empty?
        if feeds.size > 1
          Rails.cache.write_multi(feeds.to_h { [offered_key(_1.id), true] }, expires_in: OFFER_LIFETIME)
          return render json: {object: "list", data: feeds.map { FeedSerializer.new(_1).to_h }}, status: :multiple_choices
        end

        subscription = @user.subscriptions.find_or_initialize_by(feed: feeds.first)
        created = subscription.new_record?
        subscription.save!
        feeds.first.tag(tag_names(body["tag_names"]), @user) if created && body["tag_names"].present?
        render json: serialize([subscription.reload]).first, status: created ? :created : :ok
      end

      # A merge patch: custom_title (null clears it) and preferences key by key.
      def update
        body = request.request_parameters
        record = subscription
        if body.key?("custom_title")
          title = body["custom_title"]
          raise Problems::InvalidParameter.new("custom_title must be a string or null.", pointer: "/custom_title", code: "invalid_value") unless title.nil? || title.is_a?(String)
          record.title = title.presence
        end
        if body.key?("preferences")
          preferences = body["preferences"]
          raise Problems::InvalidParameter.new("preferences must be an object.", pointer: "/preferences", code: "invalid_value") unless preferences.is_a?(Hash)
          preferences.slice(*PREFERENCES).each do |key, value|
            raise Problems::InvalidParameter.new("#{key} must be true or false.", pointer: "/preferences/#{key}", code: "invalid_value") unless [true, false].include?(value)
            record[key] = value
          end
        end
        record.save!
        render json: serialize([record]).first
      end

      # PUT /subscriptions/{id}/tags: the whole set. Blank names are skipped.
      def tags
        names = request.request_parameters["tag_names"]
        raise Problems::InvalidParameter.new("tag_names must be an array of strings.", pointer: "/tag_names", code: "invalid_value") unless names.is_a?(Array) && names.all? { _1.is_a?(String) }
        record = subscription
        record.feed.tag(tag_names(names), @user)
        list = TagList.new(@user)
        tags = list.each_with_subscription_ids.select { |_tag, ids| ids.include?(record.id) }
        render_list(tags.map { |tag, ids| TagSerializer.new(tag, subscription_ids: ids).to_h })
      end

      def destroy
        record = subscription
        record.destroy
        head :no_content
      end

      # GET /subscriptions.opml: untagged feeds, then one outline per tag.
      # Only fetchable (xml) feeds: a newsletter or Pages feed URL is an
      # identifier Feedbin made, not a feed another reader can pull.
      def export
        subscriptions = @user.subscriptions.joins(:feed).merge(Feed.xml).includes(:feed).order(:id)
        titles = subscriptions.to_h { [_1.feed_id, _1.title] }
        tagged = @user.taggings.joins(:tag).pluck("tags.name", :feed_id).group_by(&:first).transform_values { |rows| rows.map(&:last) }
        tagged_feed_ids = tagged.values.flatten.to_set
        feeds = subscriptions.map(&:feed).index_by(&:id)

        outline = ->(xml, feed) { xml.outline(text: titles[feed.id], title: titles[feed.id], type: "rss", xmlUrl: feed.feed_url, htmlUrl: feed.site_url) }
        builder = ::Builder::XmlMarkup.new(indent: 2)
        builder.instruct!
        builder.opml(version: "1.0") do |opml|
          opml.head { |head| head.title("Feedbin") }
          opml.body do |body|
            feeds.each_value { |feed| outline.(body, feed) unless tagged_feed_ids.include?(feed.id) }
            tagged.keys.natural_sort_by { _1 }.each do |name|
              body.outline(text: name, title: name) do |tag|
                tagged[name].sort.each { |feed_id| feeds[feed_id] && outline.(tag, feeds[feed_id]) }
              end
            end
          end
        end
        render xml: builder.target!, content_type: "text/x-opml"
      end

      private

      # Generated subscriptions (Pages) aren't subscriptions in v3: Pages is a
      # collection. A row with no kind is an ordinary one.
      def listed_subscriptions
        @user.subscriptions.where.not(kind: :generated).or(@user.subscriptions.where(kind: nil))
      end

      def subscription
        @subscription ||= listed_subscriptions.find(params[:id])
      end

      def scope
        expand = expansions(SubscriptionSerializer::EXPANSIONS)
        scope = listed_subscriptions.order(:id)
        scope = scope.includes(feed: [*Feed::ICON_PRELOADS, :touch_icon_image_record]) if expand.include?("feed")
        scope
      end

      def serialize(subscriptions)
        expand = expansions(SubscriptionSerializer::EXPANSIONS)
        feeds = if expand.include?("feed")
          subscriptions.map(&:feed).uniq(&:id).to_h { [_1.id, FeedSerializer.new(_1).to_h] }
        else
          {}
        end
        tags = tags_by_feed_id
        subscriptions.map { SubscriptionSerializer.new(_1, tags: tags.fetch(_1.feed_id, []), feed: feeds[_1.feed_id], expand: expand).to_h }
      end

      # {feed_id => [[tag_id, name], ...]}, names in natural order.
      def tags_by_feed_id
        @user.taggings.joins(:tag).pluck(:feed_id, :tag_id, "tags.name")
          .group_by(&:first)
          .transform_values { |rows| rows.map { _1.drop(1) }.uniq.sort_by { _1.last.to_s.downcase } }
      end

      # A URL is fetched and its feeds discovered; words are searched against
      # known feeds (three at most). Any failure is "no feed found": a fetch
      # of someone else's site fails in more ways than can be listed. The
      # unexpected ones are reported.
      def discover(query)
        if query.start_with?("http") || (query.include?(".") && !query.include?(" "))
          FeedFinder.feeds(query).to_a
        else
          Feed.search(query).to_a
        end
      rescue Feedkit::Error, HTTP::Error, Addressable::URI::InvalidURIError
        []
      rescue => exception
        ErrorService.notify(exception)
        []
      end

      def offered_or_readable(id)
        feed = Feed.find_by(id: id) if id.is_a?(Integer)
        return [] unless feed && (Rails.cache.exist?(offered_key(feed.id)) || @user.can_read_feed?(feed))
        [feed]
      end

      def offered_key(feed_id)
        "v3:subscriptions:offered:#{@user.id}:#{feed_id}"
      end

      # An array, never joined: Feed#tag splits a string on commas, and a
      # folder name may contain one.
      def tag_names(names)
        Array(names).select { _1.is_a?(String) }.map(&:strip).reject(&:empty?)
      end
    end
  end
end
