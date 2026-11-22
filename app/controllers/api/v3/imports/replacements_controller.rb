module Api
  module V3
    module Imports
      # Replace All: every fixable feed of the import replaced with the first feed found at its site, in the
      # background. The import answers with those items pending.
      class ReplacementsController < ApiController
        include ImportScoped

        before_action :set_import

        def create
          @import.replace_fixable
          render_import(status: :accepted)
        end
      end
    end
  end
end
