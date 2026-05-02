require "test_helper"

class Share::EvernoteShareTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
    @entry = @feed.entries.create!(
      content: "<p>hello</p>",
      title: "Hello",
      url: "/p/1",
      public_id: SecureRandom.hex
    )
    @klass = @user.supported_sharing_services.create!(service_id: "evernote")
  end

  test "initializer is a no-op when klass has no access_token" do
    share = Share::EvernoteShare.new(@klass)
    assert_nil share.instance_variable_get(:@client)
    assert_nil share.instance_variable_get(:@token)
  end

  test "initializer wires up EvernoteOAuth client when access_token is present" do
    @klass.update!(access_token: "tok")
    fake_client = Object.new
    EvernoteOAuth::Client.stub :new, ->(*) { fake_client } do
      share = Share::EvernoteShare.new(@klass)
      assert_equal fake_client, share.instance_variable_get(:@client)
      assert_equal "tok", share.instance_variable_get(:@token)
    end
  end

  test "consumer constructs an OAuth::Consumer with Evernote site config" do
    share = Share::EvernoteShare.new
    consumer = share.consumer
    assert_kind_of OAuth::Consumer, consumer
    assert_equal "https://www.evernote.com", consumer.options[:site]
    assert_equal "/oauth", consumer.options[:request_token_path]
    assert_equal "/OAuth.action", consumer.options[:authorize_path]
    assert_equal "/oauth", consumer.options[:access_token_path]
  end

  test "request_token delegates to consumer.get_request_token with redirect_uri" do
    share = Share::EvernoteShare.new
    captured = nil
    fake_consumer = Object.new
    fake_consumer.define_singleton_method(:get_request_token) { |opts| captured = opts; :ok }
    share.stub :consumer, fake_consumer do
      assert_equal :ok, share.request_token
    end
    assert_equal share.redirect_uri, captured[:oauth_callback]
  end

  test "request_access wraps the verifier flow on the OAuth::RequestToken" do
    share = Share::EvernoteShare.new
    fake_consumer = Object.new
    fake_request_token = Object.new
    captured_verifier = nil
    fake_request_token.define_singleton_method(:get_access_token) { |opts| captured_verifier = opts; :access }
    share.stub :consumer, fake_consumer do
      OAuth::RequestToken.stub :from_hash, ->(_, _) { fake_request_token } do
        assert_equal :access, share.request_access("tok", "sec", "vrf")
      end
    end
    assert_equal "vrf", captured_verifier[:oauth_verifier]
  end

  test "redirect_uri builds the oauth_response URL for evernote" do
    share = Share::EvernoteShare.new
    assert_match %r{/supported_sharing_services/evernote/oauth_response}, share.redirect_uri
  end

  test "response_valid? requires oauth_verifier in params" do
    share = Share::EvernoteShare.new
    assert share.response_valid?({}, {oauth_verifier: "vrf"})
    refute share.response_valid?({}, {})
  end

  test "share updates default_option and delegates to authenticated_share" do
    @klass.update!(access_token: "tok")
    EvernoteOAuth::Client.stub :new, ->(*) { Object.new } do
      share = Share::EvernoteShare.new(@klass)
      share.stub :authenticated_share, ->(klass, params) { {forwarded: params[:notebook_guid]} } do
        result = share.share(notebook_guid: "guid-1", entry_id: @entry.id)
        assert_equal({forwarded: "guid-1"}, result)
      end
      assert_equal "guid-1", @klass.reload.default_option
    end
  end

  test "add returns 200 when createNote succeeds" do
    @klass.update!(access_token: "tok")
    fake_note_store = Minitest::Mock.new
    fake_note_store.expect :createNote, :note, [String, Object]
    fake_client = Object.new
    fake_client.define_singleton_method(:note_store) { fake_note_store }

    EvernoteOAuth::Client.stub :new, ->(*) { fake_client } do
      share = Share::EvernoteShare.new(@klass)
      ContentFormatter.stub :evernote_format, "<p>hello</p>" do
        ApplicationController.stub :render, "<en-note>hello</en-note>" do
          status = share.add(
            entry_id: @entry.id,
            notebook_guid: "guid",
            title: "Hello",
            tags: "a, b"
          )
          assert_equal 200, status
        end
      end
    end
    fake_note_store.verify
  end

  test "add returns 401 when AUTH_EXPIRED is raised" do
    @klass.update!(access_token: "tok")
    expired = Class.new(StandardError) do
      def errorCode
        Evernote::EDAM::Error::EDAMErrorCode::AUTH_EXPIRED
      end
    end
    fake_note_store = Object.new
    fake_note_store.define_singleton_method(:createNote) { |*| raise expired.new("expired") }
    fake_client = Object.new
    fake_client.define_singleton_method(:note_store) { fake_note_store }

    EvernoteOAuth::Client.stub :new, ->(*) { fake_client } do
      share = Share::EvernoteShare.new(@klass)
      ContentFormatter.stub :evernote_format, "<p>hello</p>" do
        ApplicationController.stub :render, "<en-note>hello</en-note>" do
          assert_equal 401, share.add(entry_id: @entry.id, notebook_guid: "guid", title: "Hi")
        end
      end
    end
  end

  test "add returns 500 and notifies ErrorService on other exceptions" do
    @klass.update!(access_token: "tok")
    fake_note_store = Object.new
    fake_note_store.define_singleton_method(:createNote) { |*| raise "boom" }
    fake_client = Object.new
    fake_client.define_singleton_method(:note_store) { fake_note_store }

    EvernoteOAuth::Client.stub :new, ->(*) { fake_client } do
      share = Share::EvernoteShare.new(@klass)
      notifications = []
      ErrorService.stub :notify, ->(opts) { notifications << opts } do
        ContentFormatter.stub :evernote_format, "<p>hello</p>" do
          ApplicationController.stub :render, "<en-note>hello</en-note>" do
            assert_equal 500, share.add(entry_id: @entry.id, notebook_guid: "guid", title: "Hi")
          end
        end
      end
      assert_equal 1, notifications.size
      assert_equal "EvernoteShare#add", notifications.first[:error_class]
    end
  end

  test "after_activate returns the notebook options hash" do
    @klass.update!(access_token: "tok")
    notebooks = [
      OpenStruct.new(name: "Personal", guid: "g1"),
      OpenStruct.new(name: "Work", guid: "g2")
    ]
    fake_note_store = Object.new
    fake_note_store.define_singleton_method(:listNotebooks) { |*| notebooks }
    fake_client = Object.new
    fake_client.define_singleton_method(:note_store) { fake_note_store }

    EvernoteOAuth::Client.stub :new, ->(*) { fake_client } do
      share = Share::EvernoteShare.new(@klass)
      assert_equal({"Personal" => "g1", "Work" => "g2"}, share.after_activate)
    end
  end

  test "note_store memoizes the underlying client.note_store" do
    @klass.update!(access_token: "tok")
    counter = 0
    note_store = Object.new
    fake_client = Object.new
    fake_client.define_singleton_method(:note_store) {
      counter += 1
      note_store
    }
    EvernoteOAuth::Client.stub :new, ->(*) { fake_client } do
      share = Share::EvernoteShare.new(@klass)
      assert_equal note_store, share.note_store
      assert_equal note_store, share.note_store
      assert_equal 1, counter
    end
  end
end
