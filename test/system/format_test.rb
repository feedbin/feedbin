require "application_system_test_case"

class FormatTest < ApplicationSystemTestCase

  test "change format" do

    show_article_setup
    @user.update(theme: "sunset")
    @user.update(font: "serif-1")
    @user.update(font_size: "5")
    login_as(@user)

    click_link(@entries.first.title)

    find("[data-behavior~=show_format_menu]").click

    assert find(".format-palette").visible?

    ["dusk", "sunset", "midnight", "day", "auto"].each do |theme|
      find("label[for='user_theme_#{theme}']").click
      wait_for_ajax
      assert_equal(theme, @user.reload.theme)
    end

    Feedbin::Application.config.fonts.each do |font|
      find("label[for='user_font_#{font.slug}']").click
      wait_for_ajax
      assert_equal(font.slug, @user.reload.font)
    end

    new_size = @user.font_size.to_i - 1
    find("[data-behavior~=decrease_font]").click
    wait_for_ajax
    assert_equal (new_size).to_s, @user.reload.font_size

    find("[data-behavior~=increase_font]").click
    wait_for_ajax
    assert_equal (new_size + 1).to_s, @user.reload.font_size

    find("label[for=toggle_full_screen]").click
    page.has_selector?('body.full-screen')

    find("label[for=user_entry_width]").click
    page.has_selector?('body.fluid-1')

  end
end