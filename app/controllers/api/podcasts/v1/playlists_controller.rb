module Api
  module Podcasts
    module V1
      class PlaylistsController < ApiController
        before_action :set_playlist, only: [:update, :destroy]
        before_action :validate_content_type, only: [:create, :update]

        def index
          @user = current_user
          @user.migrate_playlists!
          @playlists = @user.playlists
        end

        def create
          @playlist = @user.playlists.create_with(playlist_params).find_or_create_by(title: params[:playlist][:title])
        end

        def destroy
          @playlist.destroy
          head :no_content
        end

        def update
          update_params = remove_stale_updates(@playlist, playlist_params, params)
          @playlist.update(update_params)
          head :no_content
        end

        private

        def playlist_params
          params.require(:playlist).permit(:title, :sort_order)
        end

        def set_playlist
          @playlist = @user.playlists.find(params[:id])
        end
      end
    end
  end
end