class ImportsController < ApplicationController

  # POST /imports
  def create
    @user = current_user
    @import = Import.new(import_params)
    @import.user_id = @user.id

    respond_to do |format|
      if @import.save
        @import.build_import_job
        format.html { redirect_to settings_import_export_url, notice: 'Import has started.' }
      else
        @messages = @import.errors.full_messages
        flash[:error] = render_to_string partial: "shared/messages"
        format.html { redirect_to settings_import_export_url }
      end
    end
  rescue ActionController::ParameterMissing => e
    @messages = ['File is required']
    flash[:error] = render_to_string partial: "shared/messages"
    redirect_to settings_import_export_url
  end

  private

  def import_params
    params.require(:import).permit(:upload)
  end

end
