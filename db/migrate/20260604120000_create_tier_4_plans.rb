class CreateTier4Plans < ActiveRecord::Migration[7.2]
  def up
    Plan.find_or_create_by!(stripe_id: "basic-monthly-4") do |plan|
      plan.name = "Monthly"
      plan.price = 7
      plan.price_tier = 4
    end
    Plan.find_or_create_by!(stripe_id: "basic-yearly-4") do |plan|
      plan.name = "Yearly"
      plan.price = 70
      plan.price_tier = 4
    end
  end

  def down
    Plan.where(stripe_id: ["basic-monthly-4", "basic-yearly-4"]).delete_all
  end
end
