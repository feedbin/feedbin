require "test_helper"

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

  test "should parse body" do
    parser = MailtoParser.new(@link)
    assert_equal @params["body"], parser.body
  end

  test "should parse subject" do
    parser = MailtoParser.new(@link)
    assert_equal @params["subject"], parser.subject
  end

  test "should have default body" do
    email_address = Faker::Internet.email
    link = "mailto:#{@email_address}"
    parser = MailtoParser.new(link)
    assert_nil parser.body
  end

  test "should have default subject" do
    email_address = Faker::Internet.email
    link = "mailto:#{@email_address}"
    parser = MailtoParser.new(link)
    assert_nil parser.subject
  end
end
