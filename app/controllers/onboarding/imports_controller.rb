class Onboarding::ImportsController < ApplicationController
  def create
    # if rate_limited?(6, 4.hours)
    #   @error = "Too many upload requests."
    #   return
    # end

    upload = params.dig(:import, :xml)
    if upload.size > 500.kilobytes
      @error = "Import must be less than 500kb."
      return
    end

    @import = @user.imports.new(import_params)

    unless @import.save
      @error = @import.errors.full_messages.join(", ")
    end
  end

  def show
    @user = current_user
    @import = @user.imports.find(params[:id])
  end

  private

  def import_params
    params.require(:import).permit(:xml, :filename)
  end
end
