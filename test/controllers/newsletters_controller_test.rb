require 'test_helper'

class NewslettersControllerTest < ActionController::TestCase

  test "creates newsletters" do
    user = users(:ben)
    signature = Newsletter.new(newsletter_params('asdf', 'asdf')).send(:signature)
    assert_difference('Entry.count', 1) do
      post :create, newsletter_params(user.newsletter_token, signature)
    end
    assert_response :success
  end

  test "doesn't create newsletter with invalid signature" do
    user = users(:ben)
    assert_no_difference('Entry.count') do
      post :create, newsletter_params(user.newsletter_token, 'fdsa')
    end
    assert_response :success
  end

  private

  def newsletter_params(recipient, signature)
    {
      "timestamp"               => 'timestamp',
      "token"                   => 'token',
      "signature"               => signature,
      "recipient"               => "#{recipient}@development.newsletters.feedbin.com",
      "sender"                  => "ben@feedbin.com",
      "subject"                 => "This is the subject",
      "from"                    => "Ben Ubois <ben@feedbin.com>",
      "X-Mailgun-Incoming"      => "Yes",
      "X-Envelope-From"         => "<ben@feedbin.com>",
      "Received"                => "XYZ",
      "Dkim-Signature"          => "XYZ",
      "X-Google-Dkim-Signature" => "XYZ",
      "X-Gm-Message-State"      => "XYZ",
      "X-Received"              => "XYZ",
      "Return-Path"             => "<ben@feedbin.com>",
      "From"                    => "Ben Ubois <ben@feedbin.com>",
      "Content-Type"            => "multipart/alternative; boundary=\"Apple-Mail=_8AB713F4-14C8-48B5-AD4B-B694CA436A93\"",
      "Subject"                 => "This is the subject",
      "Message-Id"              => "<0B507DA2-3174-4575-8987-C2064F3D532C@feedbin.com>",
      "Date"                    => "Thu, 28 Jul 2016 18:44:38 -0700",
      "To"                      => "#{recipient}@development.newsletters.feedbin.com",
      "Mime-Version"            => "1.0 (Mac OS X Mail 9.3 \\(3124\\))",
      "X-Mailer"                => "Apple Mail (2.3124)",
      "message-headers"         => "XYZ",
      "body-plain"              => "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation .",
      "body-html"               => "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html charset=us-ascii\"></head><body style=\"word-wrap: break-word; -webkit-nbsp-mode: space; -webkit-line-break: after-white-space;\" class=\"\"><div style=\"margin: 0px; line-height: normal;\" class=\"\"><b class=\"\">Lorem ipsum</b> dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation.</div></body></html>",
      "stripped-html"           => "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html charset=us-ascii\"></head><body style=\"word-wrap: break-word; -webkit-nbsp-mode: space; -webkit-line-break: after-white-space;\" class=\"\"><div style=\"margin: 0px; line-height: normal;\" class=\"\"><b class=\"\">Lorem ipsum</b> dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation.</div></body></html>",
      "stripped-text"           => "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation .",
      "stripped-signature"      => "",
    }
  end

end
