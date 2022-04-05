class AccountMigrationsController < ApplicationController
  def index
    @user = current_user
    @migration = @user.account_migrations.last

    respond_to do |format|
      format.js
      format.html do
        render layout: "settings"
      end
    end
  end

  def start
    @user = current_user
    @migration = @user.account_migrations.find(params[:id])
    if @migration.pending?
      @migration.started!
      AccountMigrator::Setup.perform_async(@migration.id)
    end
    redirect_to account_migrations_url
  end

end
