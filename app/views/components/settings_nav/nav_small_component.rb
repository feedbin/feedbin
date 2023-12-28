module SettingsNav
  class NavSmallComponent < ApplicationComponent
    def initialize(url:, method: nil)
      @url = url
      @method = method
    end

    def template(&block)
      li class: "last:mt-4" do
        a href: @url, data_method: @method, class: "block !text-500 p-2 pl-8 rounded hover:bg-200 hover:no-underline text-sm", &block
      end
    end
  end
end
