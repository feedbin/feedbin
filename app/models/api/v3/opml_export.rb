require "builder"

module Api
  module V3
    # The user's subscriptions as OPML: untagged feeds, then one outline per
    # tag. Only fetchable (xml) feeds: a newsletter or Pages feed URL is an
    # identifier Feedbin made, not a feed another reader can pull.
    class OpmlExport
      def initialize(user)
        @user = user
      end

      def to_xml
        builder = ::Builder::XmlMarkup.new(indent: 2)
        builder.instruct!
        builder.opml(version: "1.0") do |opml|
          opml.head { |head| head.title("Feedbin") }
          opml.body do |body|
            feeds.each_value { |feed| outline(body, feed) unless tagged_feed_ids.include?(feed.id) }
            tagged.keys.natural_sort_by { _1 }.each do |name|
              body.outline(text: name, title: name) do |tag|
                tagged[name].sort.each { |feed_id| feeds[feed_id] && outline(tag, feeds[feed_id]) }
              end
            end
          end
        end
        builder.target!
      end

      private

      def outline(xml, feed)
        title = titles[feed.id]
        xml.outline(text: title, title: title, type: "rss", xmlUrl: feed.feed_url, htmlUrl: feed.site_url)
      end

      def subscriptions
        @subscriptions ||= @user.subscriptions.joins(:feed).merge(Feed.xml).includes(:feed).order(:id).to_a
      end

      def feeds
        @feeds ||= subscriptions.map(&:feed).index_by(&:id)
      end

      def titles
        @titles ||= subscriptions.to_h { [_1.feed_id, _1.title] }
      end

      # {tag name => [feed_id, ...]}
      def tagged
        @tagged ||= @user.taggings.joins(:tag).pluck("tags.name", :feed_id).group_by(&:first).transform_values { |rows| rows.map(&:last) }
      end

      def tagged_feed_ids
        @tagged_feed_ids ||= tagged.values.flatten.to_set
      end
    end
  end
end
