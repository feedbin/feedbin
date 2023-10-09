class Settings::ImportsController < ApplicationController

  def index
    @user = current_user
    @tags = @user.feed_tags
    @download_options = @tags.map { |tag|
      [tag.name, tag.id]
    }
    @download_options.unshift(["All", "all"])
    @imports = @user.imports.where.not(filename: nil).order(created_at: :desc)
    render layout: "settings"
  end

  def show
    @user = current_user
    @import = @user.imports.find(params[:id])
    respond_to do |format|
      format.js
      format.html do
        render Settings::Imports::ShowView.new(import: @import), layout: "settings"
      end
    end
  end

  def create
    if rate_limited?(6, 4.hours)
      redirect_to settings_import_export_url, alert: "Too many upload requests."
      return
    end

    upload = params.dig(:import, :upload)
    if !upload.respond_to?(:tempfile)
      redirect_to settings_import_export_url, alert: "No file uploaded."
      return
    elsif upload.tempfile.size > 500.kilobytes
      redirect_to settings_import_export_url, alert: "Import must be less than 500kb."
      return
    end

    @import = @user.imports.new(filename: upload.original_filename, xml: upload.tempfile.read)

    if @import.save
      redirect_to settings_import_url(@import), notice: "Import has started."
    else
      @messages = @import.errors.full_messages
      flash[:error] = render_to_string partial: "shared/messages"
      redirect_to settings_import_export_url
    end
  end

  def replace_all
    @user = current_user
    @import = @user.imports.find(params[:id])
    @import.import_items.fixable.each do |import_item|
      import_item.complete!
      FeedImportFixer.perform_async(@user.id, import_item.id)
    end
    redirect_to settings_import_url(@import), notice: "Imports replaced."
  end
end
