require "test_helper"

class AccountMigrationsControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
  end

  test "index assigns the user's most recent migration" do
    older = @user.account_migrations.create!(api_token: "old")
    newer = @user.account_migrations.create!(api_token: "new")

    login_as @user
    get :index
    assert_response :success
    assert_equal newer, assigns(:migration)
  end

  test "start moves a pending migration to started and enqueues setup" do
    migration = @user.account_migrations.create!(api_token: "tok")
    AccountMigrator::Setup.jobs.clear

    login_as @user
    post :start, params: {id: migration.id}

    assert migration.reload.started?
    assert_equal 1, AccountMigrator::Setup.jobs.size
    assert_equal [migration.id], AccountMigrator::Setup.jobs.last["args"]
    assert_redirected_to account_migrations_url
  end

  test "start does nothing when the migration is not pending" do
    migration = @user.account_migrations.create!(api_token: "tok", status: :complete)
    AccountMigrator::Setup.jobs.clear

    login_as @user
    post :start, params: {id: migration.id}

    assert migration.reload.complete?
    assert_equal 0, AccountMigrator::Setup.jobs.size
  end
end
