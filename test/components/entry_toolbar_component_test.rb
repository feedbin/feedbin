require "test_helper"

class EntryToolbarComponentTest < ComponentTestCase
  CONTROLLER = Rails.root.join("app/javascript/controllers/entry_toolbar_controller.js")

  test "renders the controller root with url templates" do
    root = toolbar.at_css("[data-controller~='entry-toolbar']")
    assert_equal "/entries/ENTRY_ID/starred_entries", root["data-entry-toolbar-starred-url-value"]
    assert_equal "/entries/ENTRY_ID/unread_entries", root["data-entry-toolbar-unread-url-value"]
    assert_equal "/extracts/ENTRY_ID/entry", root["data-entry-toolbar-extract-url-value"]
    assert_equal "/entries/ENTRY_ID", root["data-entry-toolbar-delete-url-value"]
    assert_equal "/settings/sticky/FEED_ID", root["data-entry-toolbar-sticky-url-value"]
    assert_equal "/subscriptions/FEED_ID/edit?app=true", root["data-entry-toolbar-edit-subscription-url-value"]
    assert_equal "0", root["data-entry-toolbar-entry-id-value"]
    %w[starred read extract loading pages subscribed].each do |name|
      assert_equal "false", root["data-entry-toolbar-#{name}-value"], name
    end
  end

  test "has no forms" do
    assert_empty toolbar.css("form")
  end

  test "keeps the copy-link field" do
    assert toolbar.at_css("textarea#source_link_field")
  end

  # Stimulus reads an undeclared value as undefined and calls a missing
  # action not at all, so neither mistake shows up as an error on the page.
  test "every rendered value is declared by the controller" do
    root = toolbar.at_css("[data-controller~='entry-toolbar']")
    rendered = root.attributes.keys.filter_map { it[/\Adata-entry-toolbar-(.+)-value\z/, 1] }
      .map { it.underscore.camelize(:lower) }
    declared = File.read(CONTROLLER)[/static values = \{(.*?)\}/m, 1].to_s.scan(/(\w+):/).flatten

    assert_operator rendered.length, :>, 0
    assert_empty rendered - declared
  end

  test "every rendered action names a controller method" do
    actions = toolbar.css("[data-action]").flat_map { it["data-action"].scan(/->entry-toolbar#(\w+)/).flatten }.uniq
    source = File.read(CONTROLLER)

    assert_operator actions.length, :>, 0
    missing = actions.reject { source.match?(/^\s+(async\s+)?#{it}\(/) }
    assert_empty missing
  end

  private

  def toolbar
    @toolbar ||= Nokogiri::HTML5.fragment(render(App::EntryToolbarComponent.new).to_s)
  end
end
