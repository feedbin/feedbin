module Api
  module V2
    class UsersController < ApiController
      respond_to :json

      before_action :validate_content_type, only: [:create]
      skip_before_action :authorize, only: [:create]
      skip_before_action :valid_user

      def create
        @user = User.new(user_params)
        @user.plan = Plan.find_by_stripe_id("trial")
        @user.password_confirmation = user_params.try(:user).try(:password)
        if @user.save
          render status: :created
        else
          render json: {errors: @user.errors.full_messages.uniq}, status: :bad_request
        end
      end

      def info
        @user = current_user
      end

      def destroy
        @user = current_user
        if params[:silent] == "false"
          UserDeleter.perform_async(@user.id)
        else
          @user.destroy
        end
      end

      def update
        @user = current_user
        @user.update(user_update_params)
      end

      private

      def user_params
        params.require(:user).permit(:email, :password)
      end

      def user_update_params
        params.require(:user).permit(:podcast_sort_order)
      end
    end
  end
end
