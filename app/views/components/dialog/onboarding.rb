module Dialog
  class Onboarding < ApplicationComponent
    def view_template
      # server rendered open so it is visible at first paint, before Stimulus
      # connects and upgrades it to a modal
      dialog open: true, class: "fixed z-[10000] p-0 m-0 border-none bg-transparent inset-0 h-dvh w-screen max-h-dvh max-w-[100vw] data-[closing=true]:animate-fade-out" do
        render ::Onboarding::ShowView.new
      end
    end
  end
end
