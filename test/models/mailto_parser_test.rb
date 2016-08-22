require 'test_helper'

class MailtoParserTest < ActiveSupport::TestCase

  setup do
    @params = {
      "body" => "this is the body",
      "subject" => "this is the subject",
    }
    @email_address = Faker::Internet.email
    @link = "mailto:#{@email_address}?#{@params.to_query}"
  end

  test "should parse email address" do
    parser = MailtoParser.new(@link)
    assert_equal(@email_address, parser.email)
  end

  test "should parse params" do
    parser = MailtoParser.new(@link)
    @params.each do |param, value|
      assert_equal(value, parser.params[param])
    end
  end

end
