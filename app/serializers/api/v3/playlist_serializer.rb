module Api
  module V3
    class PlaylistSerializer
      SORTS = {"custom" => "manual", "newest_first" => "published_desc", "oldest_first" => "published_asc"}.freeze

      def initialize(playlist)
        @playlist = playlist
      end

      def to_h
        {
          object: "playlist",
          id: @playlist.id,
          title: @playlist.title,
          sort: SORTS.fetch(@playlist.sort_order),
          created_at: @playlist.created_at.utc.iso8601,
          updated_at: @playlist.updated_at.utc.iso8601
        }
      end
    end
  end
end
