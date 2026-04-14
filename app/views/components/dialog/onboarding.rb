module Dialog
  class Onboarding < ApplicationComponent
    def view_template
      dialog class: "p-0 m-0 border-none bg-transparent inset-0 h-dvh w-screen max-h-dvh max-w-[100vw]" do
        render ::Onboarding::ShowView.new
      end
    end
  end
end
