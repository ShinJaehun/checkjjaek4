require "rails_helper"

RSpec.describe Admin::UsersHelper, type: :helper do
  it "uses the same account labels and colors in badges and filters" do
    expect(helper.admin_user_status_filter_options).to eq([
      ["정상", "active"], ["운영 정지", "suspended"], ["본인 탈퇴", "withdrawn"]
    ])
    expect(helper.admin_user_status_badge_classes(:active)).to include("bg-emerald-100")
    expect(helper.admin_user_status_badge_classes(:suspended)).to include("bg-red-100")
    expect(helper.admin_user_status_badge_classes(:withdrawn)).to include("bg-stone-200")
  end

  it "preserves overlapping roles and internal filter values" do
    admin = User.new(global_admin: true)
    regular = User.new(global_admin: false)

    expect(helper.admin_user_role_keys(admin, has_administered_groups: true)).to eq(%w[global_admin group_admin])
    expect(helper.admin_user_role_keys(regular, has_administered_groups: false)).to eq(["regular"])
    expect(helper.admin_user_role_filter_options).to eq([
      ["시스템 관리자", "global_admin"], ["동아리 관리자", "group_admin"], ["일반 사용자", "regular"]
    ])
    expect(helper.admin_user_role_badge_classes(:global_admin)).to include("bg-amber-100")
    expect(helper.admin_user_role_badge_classes(:group_admin)).to include("bg-sky-100")
    expect(helper.admin_user_role_badge_classes(:regular)).to include("bg-stone-100")
    I18n.with_locale(:en) { expect(helper.admin_user_role_label(:global_admin)).to eq("System admin") }
  end
end
