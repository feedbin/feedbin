module Api
  module V2
    class TaggingsController < ApiController
      respond_to :json
      before_action :validate_create, only: [:create]
      before_action :validate_content_type, only: [:create]

      def index
        @user = current_user
        @taggings = @user.taggings.includes(:tag)
        fresh_when last_modified: @taggings.maximum(:updated_at), etag: @taggings.map(&:id)
      end

      def show
        @user = current_user
        @tagging = @user.taggings.where(id: params[:id]).first
        if @tagging.present?
          fresh_when(@tag)
        else
          status_forbidden
        end
      end

      def create
        @user = current_user
        name = params[:name]
        return status_bad_request([{name: "Must be a non-blank string"}]) unless name.is_a?(String) && name.strip.present?

        @feed = @user.feeds.where(id: params[:feed_id]).first
        if @feed.present?
          @tagging = Tagging.joins(:tag).where(taggings: {feed_id: params[:feed_id], user_id: @user.id}, tags: {name: name.strip}).first
          if @tagging.present?
            status = :found
          else
            # Feed#tag can still come back empty, and the location header needs
            # an id — so decide the status from the record, not before it.
            @tagging = @feed.tag(name, @user, false).first
            return status_bad_request([{name: "Could not be used as a tag"}]) if @tagging.blank?
            status = :created
          end
          render status: status, location: api_v2_tagging_url(@tagging, format: :json)
        else
          status_forbidden
        end
      end

      def destroy
        @user = current_user
        @tagging = @user.taggings.where(id: params[:id]).first
        if @tagging.present?
          @tagging.destroy
          head :no_content
        else
          status_forbidden
        end
      end

      private

      def validate_create
        needs "feed_id", "name"
      end
    end
  end
end
