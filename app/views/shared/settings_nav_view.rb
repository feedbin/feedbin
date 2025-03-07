module Shared
  class SettingsNavView < ApplicationView

    def initialize(user:)
      @user = user
    end

    def view_template
      div(class: "group-data-[nav=modal]:-mt-4") do
        render ::SettingsNav::HeaderComponent.new do
          plain " General "
        end
      end

      ul do
        render(::SettingsNav::NavComponent.new(
          title: "Feedbin",
          subtitle: "Back to the app",
          url: root_path,
          icon: "menu-icon-app",
          classes: "md:hidden"
        ))
        render(::SettingsNav::NavComponent.new(
          title: "Settings",
          subtitle: "General preferences",
          url: settings_path,
          icon: "menu-icon-settings",
          selected: is_active?("settings", "index")
        ))
        render(::SettingsNav::NavComponent.new(
          title: "Subscriptions",
          subtitle: "Manage feeds",
          url: settings_subscriptions_path,
          icon: "menu-icon-subscriptions",
          selected: is_active?(["settings/subscriptions", "fix_feeds"], %w[index edit]),
          notification: current_user.setting_on?(:fix_feeds_available)
        ))
        render(::SettingsNav::NavComponent.new(
          title: "Newsletters",
          subtitle: "Addresses & senders",
          url: settings_newsletters_path,
          icon: "menu-icon-newsletters",
          selected: is_active?(["settings/newsletters", "settings/newsletters/senders", "settings/newsletters/addresses"], %w[index show new])
        ))
      end

      render ::SettingsNav::HeaderComponent.new do
        plain " Tools"
      end

      div(class: "px-4 pl-10 tw-hidden group-data-[nav=dropdown]:block") do
        hr(class: "m-0")
      end

      ul do
        render(::SettingsNav::NavComponent.new(
          title: "Actions",
          subtitle: "Filters & more",
          url: actions_path,
          selected: is_active?(["actions"], %w[index new edit]),
          icon: "menu-icon-actions"
        ))
        render(::SettingsNav::NavComponent.new(
          title: "Share & Save",
          subtitle: "Social plugins",
          url: sharing_services_path,
          selected: is_active?("sharing_services", "index"),
          icon: "menu-icon-share-save"
        ))
        render(::SettingsNav::NavComponent.new(
          title: "Import & Export",
          subtitle: "Bring your OPML",
          url: settings_import_export_path,
          selected: is_active?(["settings/imports"], %w[index show]),
          icon: "menu-icon-import-export"
        ))
      end

      render ::SettingsNav::HeaderComponent.new do
        plain " Admin"
      end

      div(class: "px-4 pl-10 tw-hidden group-data-[nav=dropdown]:block") do
        hr(class: "m-0")
      end

      ul do
        render(::SettingsNav::NavComponent.new(
          title: "Account",
          subtitle: "Update email & password",
          url: settings_account_path,
          selected: is_active?("settings", "account"),
          icon: "menu-icon-account"
        ))
        if ENV["STRIPE_API_KEY"]
          render(::SettingsNav::NavComponent.new(
            title: "Billing",
            subtitle: "Payment method & plan",
            url: settings_billing_path,
            selected: is_active?(["settings/billings"], %w[index edit payment_history]),
            icon: "menu-icon-billing"
          ))
        end
      end

      if @user.try(:admin?)
        render ::SettingsNav::HeaderComponent.new do
          plain " Internal"
        end

        div(class: "px-4 pl-10 tw-hidden group-data-[nav=dropdown]:block") do
          hr(class: "m-0")
        end
        ul do
          render(::SettingsNav::NavComponent.new(
            title: "Customers",
            subtitle: "Manage customers",
            url: admin_users_path,
            selected: is_active?("admin/users", "index"),
            icon: "menu-icon-customers"
          ))
          render(::SettingsNav::NavComponent.new(
            title: "Feeds",
            subtitle: "Feed info",
            url: admin_feeds_path,
            selected: is_active?("admin/feeds", "index"),
            icon: "menu-icon-feeds"
          ))
          render(::SettingsNav::NavComponent.new(
            title: "Sidekiq",
            subtitle: "Background jobs",
            url: sidekiq_web_path,
            icon: "menu-icon-sidekiq"
          ))
          render(::SettingsNav::NavComponent.new(
            title: "Lookbook",
            subtitle: "Feedkit components",
            url: "/lookbook",
            icon: "menu-icon-lookbook"
          ))
        end
      end

      div(class: "px-4 pl-10 tw-hidden group-data-[nav=dropdown]:block") do
        hr(class: "m-0")
      end

      ul(class: "tw-hidden group-data-[nav=dropdown]:block") do
        render(::SettingsNav::NavComponent.new(
          title: "Sign Out",
          url: [logout_path, { method: :delete }],
          icon: "menu-icon-log-out"
        ))
      end

      div(class: "group-data-[nav=dropdown]:hidden") do
        div(class: "p-4 group-data-[nav=modal]:py-0") { hr }
        ul do
          render ::SettingsNav::NavSmallComponent.new url: "/home" do
            "Home"
          end
          render ::SettingsNav::NavSmallComponent.new url: "/blog" do
            "Blog"
          end
          render ::SettingsNav::NavSmallComponent.new url: "/apps" do
            "Apps"
          end
          render ::SettingsNav::NavSmallComponent.new url: "/help" do
            "Help"
          end
          render ::SettingsNav::NavSmallComponent.new url: "https://github.com/feedbin/feedbin-api#readme" do
            "API"
          end
          render ::SettingsNav::NavSmallComponent.new url: "/privacy-policy" do
            "Privacy Policy"
          end
          render ::SettingsNav::NavSmallComponent.new url: "mailto:support@feedbin.com" do
            "Email"
          end
          render ::SettingsNav::NavSmallComponent.new url: "https://feedbin.social/@feedbin" do
            "Mastodon"
          end
          render ::SettingsNav::NavSmallComponent.new url: logout_path, method: "delete" do
            "Sign Out"
          end
        end
      end
    end

  end
end
