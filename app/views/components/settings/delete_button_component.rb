module Settings
  class DeleteButtonComponent < ApplicationComponent
    def initialize(url:, confirm:)
      @url = url
      @confirm = confirm
    end

    def view_template(&)
      form_with(url: @url, method: :delete) do
        button(class: "button button-secondary", data: {confirm: @confirm}, &)
      end
    end
  end
end
