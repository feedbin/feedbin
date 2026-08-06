require "test_helper"

# There is no JS test runner in this project, so these assert against the real
# source. Both defects are silent by construction -- a repeated attribute is
# discarded by the HTML parser and an undeclared Stimulus value reads as
# undefined -- so neither shows up at runtime as an error.
class ToolbarWiringTest < ActiveSupport::TestCase
  LAYOUT = Rails.root.join("app/views/site/logged_in.html.erb")
  CONTROLLER = Rails.root.join("app/javascript/controllers/toolbar_controller.js")

  test "no element declares data-action more than once" do
    offenders = File.readlines(LAYOUT).each_with_index.filter_map { |line, index|
      "#{LAYOUT.basename}:#{index + 1}" if line.scan(/\bdata-action=/).length > 1
    }

    assert_empty offenders,
      "a repeated data-action is a parse error; the duplicate is discarded"
  end

  test "the entries container keeps the actions it declares" do
    entries = File.readlines(LAYOUT).find { _1.include?("class=\"entries\"") }

    assert entries, "the entries container moved"
    assert_match "scroll->toolbar#scroll", entries
    # mousemove is the escape hatch for the toolbar that scroll hides, and no
    # ancestor of the entries column declares it.
    assert_match "mousemove->toolbar#mousing", entries
  end

  test "the toolbar controller only reads values it declares" do
    source = File.read(CONTROLLER)
    declared = source[/static values = \{(.*?)\}/m, 1].to_s.scan(/(\w+):/).flatten

    code = source.gsub(%r{//.*$}, "").gsub(%r{/\*.*?\*/}m, "")
    used = code.scan(/this\.(\w+)Value\b/).flatten.uniq

    assert_empty used - declared,
      "reads an undeclared Stimulus value, which is silently undefined"
  end
end
