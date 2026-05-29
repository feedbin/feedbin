module Billing
  class StatusComponent < ApplicationComponent
    include Phlex::Rails::Helpers::Routes
    register_value_helper :number_to_currency
    register_value_helper :form_authenticity_token

    def initialize(user:, plans:, default_plan:)
      @user = user
      @plans = plans
      @default_plan = default_plan
    end

    def view_template
      if @user.plan.stripe_id == "free"
        render_free
      elsif @user.timed_plan?
        render_timed
      elsif @user.app_plan?
        render_app
      else
        render_default
      end
    end

    private

    def render_free
      render Settings::ControlGroupComponent.new(class: "mb-14") do |group|
        group.header { "Your Plan" }
        group.item do
          render Settings::ControlRowComponent.new do |row|
            row.title { "Free for life" }
          end
        end
      end
    end

    def render_timed
      render Settings::ControlGroupComponent.new(class: "mb-14") do |group|
        group.header { "Your Plan" }
        group.item do
          render Settings::ControlRowComponent.new do |row|
            row.title { "Prepaid" }
            row.control do
              if @user.timed_plan_expired?
                span(class: "text-red-600") { "Expired" }
              else
                span do
                  strong(class: "font-bold") { "Expires:" }
                  plain " "
                  plain @user.expires_at.to_formatted_s(:date)
                end
              end
            end
          end
        end
        group.description { "You can purchase more time using Feedbin Notifier." }
      end

      render Billing::SubscribeFormComponent.new(
        publishable_key: STRIPE_PUBLIC_KEY,
        plans: @plans,
        default_plan: @default_plan,
        subscribe_title: "Switch to Subscription",
        mode: @user.trial_end.future? ? "setup" : "payment",
        user: @user
      )

      render_payment_history
      render_receipt_info
    end

    def render_app
      render Settings::ControlGroupComponent.new(class: "mb-14") do |group|
        group.header { "Your Plan" }
        group.item do
          render Settings::ControlRowComponent.new do |row|
            row.title { "In-App Subscription" }
          end
        end
        group.description { "You can manage your subscription in the Feedbin app." }
      end

      render_payment_history
      render_receipt_info
    end

    def render_default
      render Settings::ControlGroupComponent.new(class: "mb-14") do |group|
        group.header { "Payment Information" }
        group.item do
          render Settings::ControlRowComponent.new do |row|
            row.title do
              span(data: {behavior: "billing_details"}, class: "text") { "Loading…" }
            end
            row.control do
              link_to "Edit", edit_settings_billing_path
            end
          end
        end
      end

      render Settings::ControlGroupComponent.new(class: "mb-14") do |group|
        group.header { "Change Your Plan" }
        @plans.each do |plan|
          group.item do
            render Settings::ControlRowComponent.new do |row|
              row.title { "#{number_to_currency(plan.price, precision: 0)}/#{plan.period}" }
              row.control do
                if @user.plan.id == plan.id
                  plain "Your plan"
                else
                  render_change_plan_form(plan)
                end
              end
            end
          end
        end
        group.description { "Plan changes are pro-rated." }
      end

      render_payment_history
      render_receipt_info
    end

    def render_change_plan_form(plan)
      form(action: update_plan_settings_billing_path, method: "post", class: "no-margin", data: {behavior: "change_plan"}) do
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token, autocomplete: "off")
        input(type: "hidden", name: "plan", id: "plan", value: plan.id, autocomplete: "off")
        button(
          type: "submit",
          class: "button-text text-normal text-blue-600",
          data: {confirm: "Are you sure you want to switch to #{plan.name.downcase} billing?"}
        ) { "Switch to this plan" }
      end
    end

    def render_payment_history
      render partial("shared/billing/payment_history", limit: 12)
    end

    def render_receipt_info
      render partial("shared/billing/receipt_info")
    end
  end
end
