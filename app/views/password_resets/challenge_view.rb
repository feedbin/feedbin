class PasswordResets::ChallengeView < ApplicationView
  def initialize(email:, turnstile_site_key:)
    @email = email
    @turnstile_site_key = turnstile_site_key
  end

  def view_template
    div(class: "border rounded-md p-6 md:p-12 mb-8", data: stimulus(controller: :turnstile, values: {sitekey: @turnstile_site_key})) do
      h1(class: "font-bold text-lg mb-4") { "Checking…" }

      form_tag(password_resets_path, novalidate: "novalidate", data: stimulus_item(target: :form, for: :turnstile)) do
        hidden_field_tag(:email, @email)
        div(data: stimulus_item(target: :widget, for: :turnstile))
      end
    end

    p(class: "text-center text-500") { "Already have an account?" }
    p(class: "text-center") { link_to("Sign In", login_path, class: "font-medium") }
  end
end
