# expand=a,b: the related objects and optional bodies a response adds to its
# default shape, which carries ids. Each controller says which names it takes.
module Api
  module V3
    module Expansion
      extend ActiveSupport::Concern

      private

      def expansions(allowed)
        @expansions ||= begin
          names = params[:expand].to_s.split(",").map(&:strip).reject(&:empty?).uniq
          unknown = names - allowed
          if unknown.any?
            raise Problems::InvalidParameter.new("expand must be a comma-separated list of #{allowed.join(", ")}.", pointer: "expand", code: "invalid_value")
          end
          names
        end
      end
    end
  end
end
