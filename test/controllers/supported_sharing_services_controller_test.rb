require "test_helper"

class SupportedSharingServicesControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @service = @user.supported_sharing_services.create(service_id: "kindle")
  end

  test "should create supported sharing service" do
    login_as @user
    assert_difference "SupportedSharingService.count", +1 do
      post :create, params: {supported_sharing_service: {service_id: "email"}}
      assert_redirected_to sharing_services_url
    end
  end

  test "should destroy supported sharing service" do
    login_as @user
    assert_difference "SupportedSharingService.count", -1 do
      delete :destroy, params: {id: @service}
      assert_redirected_to sharing_services_url
    end
  end

  test "should update supported sharing service" do
    login_as @user
    attributes = {email_name: "email_name", email_address: "email_address", kindle_address: "kindle_address"}
    patch :update, params: {id: @service, supported_sharing_service: attributes}
    assert_redirected_to sharing_services_url
    attributes.each do |attribute, value|
      assert_equal(value, @service.reload.send(attribute))
    end
  end

  test "should get completions" do
    options = ["test@test.com", "test@example.com"]
    @service.update(service_options: {completions: options})
    login_as @user
    get :autocomplete, params: {id: @service, query: "test"}
    assert_response :success
    data = JSON.parse(@response.body)
    assert data.length, options.length
  end

  test "should authorize with oauth" do
    code = "code"
    token = "access_token"

    stub_request(:post, Share::Pocket.new.url_for(:oauth_request).to_s)
      .to_return(body: {code: code}.to_json, status: 200)

    login_as @user
    post :create, params: {supported_sharing_service: {service_id: "pocket", operation: "authorize"}}
    assert_redirected_to Share::Pocket.new.authorize_url(code)

    stub_request(:post, Share::Pocket.new.url_for(:oauth_authorize).to_s)
      .with(body: hash_including({"code" => code}))
      .to_return(body: {access_token: token}.to_json, status: 200)

    assert_difference "SupportedSharingService.count", +1 do
      get :oauth_response, params: {id: "pocket"}
      assert_redirected_to sharing_services_url
    end

    pocket = @user.supported_sharing_services.where(service_id: "pocket").take
    assert_equal token, pocket.settings["access_token"]
  end

  test "should authorize with oauth2" do
    code = "code"
    token = "access_token"
    service_id = "mastodon"
    mastodon_host = "example.social"
    client_id = "client_id"
    client_secret = "client_secret"
    access_token = "access_token"
    redirect = Rails.application.routes.url_helpers.oauth2_response_supported_sharing_service_url(service_id, host: ENV["PUSH_URL"], mastodon_host: mastodon_host)

    server_response = {
      id:            "1",
      website:       ENV["PUSH_URL"],
      client_id:     client_id,
      client_secret: client_secret,
      redirect_uri:  redirect,
    }

    token_response = {
      token_type:    "Bearer",
      scope:         "write:statuses",
      created_at:    Time.now.utc.to_i,
      access_token:  access_token,
      refresh_token: nil,
      expires_at:    nil
    }

    login_as @user

    stub_request(:post, "https://#{mastodon_host}/api/v1/apps")
      .with(body: {
        client_name:   "Feedbin",
        redirect_uris: redirect,
        scopes:        "write:statuses",
        website:       ENV["PUSH_URL"]
      })
      .to_return(status: 200, body: server_response.to_json, headers: {content_type: "application/json"})

    assert_difference -> { OauthServer.count }, +1 do
      post :create, params: {mastodon_url: mastodon_host, supported_sharing_service: {service_id: service_id, operation: "authorize"}}
      assert_response :redirect
      assert_match %r{^https://example.social/oauth/authorize}, @response.redirect_url
    end

    stub_request(:post, "https://#{mastodon_host}/oauth/token")
      .with(body: {
        client_id:     client_id,
        client_secret: client_secret,
        code:          code,
        redirect_uri:  redirect,
        grant_type:    "authorization_code",
        scope:         "write:statuses"
      })
      .to_return(status: 200, body: token_response.to_json, headers: {content_type: "application/json"})

    assert_difference -> { SupportedSharingService.count }, +1 do
      get :oauth2_response, params: {id: service_id, code: code, mastodon_host: mastodon_host}
      assert_redirected_to sharing_services_url
    end

    share_data = {
      status: "status",
      spoiler_text: "spoiler_text",
      visibility: "public"
    }

    stub_request(:post, "https://example.social/api/v1/statuses").
      with(
        body: JSON.dump(share_data),
        headers: {
          'Authorization'=>'Bearer access_token',
        }).
        to_return(status: 200, body: "", headers: {})

    entry = create_entry(Feed.first)
    share = SupportedSharingService.last
    post :share, params: {id: share, entry_id: entry.id}.merge(share_data), xhr: true
    assert_response :success
  end

  test "should share" do
    Sidekiq::Worker.clear_all
    @service.update(kindle_address: "example@example.com")
    login_as @user
    assert_difference "MakeEpub.jobs.size", +1 do
      post :share, params: {id: @service, entry_id: 1}, xhr: true
      assert_response :success
    end
  end
end
