module SuperAdmin::FeaturesHelper
  def self.available_features
    YAML.load(ERB.new(Rails.root.join('app/helpers/super_admin/features.yml').read).result).with_indifferent_access
  end

  def self.plan_details
    plan = ChatwootHub.pricing_plan
    quantity = ChatwootHub.pricing_plan_quantity

    plan_name = case plan
                when 'community' then '社区版 (Community)'
                when 'premium' then '高级版 (Premium)'
                when 'enterprise' then '企业版 (Enterprise)'
                else plan
                end

    if plan == 'premium'
      "您当前使用的是 <span class='font-semibold'>#{plan_name}</span>，拥有 <span class='font-semibold'>#{quantity} 个坐席配额</span>。"
    else
      "您当前使用的是 <span class='font-semibold'>#{plan_name}</span>。"
    end
  end
end
