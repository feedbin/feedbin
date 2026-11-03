module Api
  module V3
    # Airshow playlists: the list with an ETag, create (find by title),
    # update and delete. The writes are PlaylistWrite.
    class PlaylistsController < ApiController
      before_action :set_playlist, only: [:update, :destroy]

      def index
        @user.migrate_playlists!
        data = @user.playlists.order(Arel.sql("lower(title)"), :id).map { PlaylistSerializer.new(_1).to_h }
        return if not_modified?(etag_for("playlists", digest(data)))
        render_list(data)
      end

      def create
        playlist, created = PlaylistWrite.new(@user, body).create
        render json: PlaylistSerializer.new(playlist).to_h, status: created ? :created : :ok
      end

      def update
        PlaylistWrite.new(@user, body).update(@playlist)
        render json: PlaylistSerializer.new(@playlist).to_h
      end

      # Queue rows and podcast subscriptions in it lose their playlist_id.
      def destroy
        @playlist.destroy
        head :no_content
      end

      private

      def set_playlist
        @playlist = @user.playlists.find(params[:id])
      end
    end
  end
end
