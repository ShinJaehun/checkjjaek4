require "rails_helper"

RSpec.describe "Personal group membership order", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "order-reader@example.com", password: "password123!") }
  let!(:owner) { User.create!(name: "Owner", email: "order-owner@example.com", password: "password123!") }
  let!(:memberships) do
    3.times.map do |index|
      group = Group.create!(group_admin: owner, name: "Club #{index}", lifecycle_status: :active,
                            group_type: :private_group, created_at: Time.zone.parse("2026-10-20 12:00:00") + index.days)
      group.group_memberships.create!(user:, status: :active)
    end
  end

  def index_group_paths
    Nokogiri::HTML(response.body).css("[data-group-grid] article h3 a").map { |link| link["href"] }
  end

  def edit_membership_ids
    Nokogiri::HTML(response.body).css("input[name='membership_ids[]']").map { |input| input["value"].to_i }
  end

  it "requires sign in for both editing and saving" do
    get edit_groups_membership_order_path
    expect(response).to redirect_to(new_user_session_path)
    patch groups_membership_order_path, params: { membership_ids: memberships.map(&:id) }
    expect(response).to redirect_to(new_user_session_path)
    expect(memberships.map { |membership| membership.reload.position }).to eq([ nil, nil, nil ])
  end

  it "shows the initial order and a separate complete editing list without changing positions" do
    sign_in user
    get groups_path
    expect(index_group_paths).to eq(memberships.reverse.map { |membership| group_path(membership.group) })
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("a[href='#{edit_groups_membership_order_path}']").text.strip).to eq(I18n.t("groups.membership_order.action"))
    get edit_groups_membership_order_path

    expect(response).to have_http_status(:ok)
    expect(edit_membership_ids).to eq(memberships.reverse.map(&:id))
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("form[action='#{groups_membership_order_path}']")).to be_present
    expect(page.at_css("a[href='#{groups_path}']")).to be_present
    expect(page.css("[data-group-membership-sort-handle]")).to be_empty
    expect(page.css("button[data-action='group-membership-sort#moveUp']").size).to eq(3)
    expect(page.css("button[data-action='group-membership-sort#moveDown']").size).to eq(3)
    expect(memberships.map { |membership| membership.reload.position }).to eq([ nil, nil, nil ])
  end

  %i[html turbo_stream].each do |format|
    it "saves the full #{format} form and preserves its order after refreshing" do
      sign_in user
      ids = [ memberships.second.id, memberships.last.id, memberships.first.id ]

      patch groups_membership_order_path, params: { membership_ids: ids }, as: format

      expect(response).to redirect_to(groups_path)
      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to eq(I18n.t("groups.membership_order.saved"))
      2.times do
        get groups_path
        expect(index_group_paths).to eq([ memberships.second, memberships.last, memberships.first ].map { |membership| group_path(membership.group) })
      end
      get edit_groups_membership_order_path
      expect(edit_membership_ids).to eq(ids)
      expect(owner.group_memberships.pluck(:position)).to all(be_nil)
    end
  end

  it "keeps each user's chosen order independent" do
    sign_in user
    patch groups_membership_order_path, params: { membership_ids: memberships.map(&:id) }
    sign_in owner
    owned = owner.group_memberships.order(:id).to_a
    owner_ids = [ owned.second.id, owned.first.id, owned.last.id ]
    patch groups_membership_order_path, params: { membership_ids: owner_ids }
    expect(response).to redirect_to(groups_path)
    get groups_path
    expect(index_group_paths).to eq([ owned.second, owned.first, owned.last ].map { |membership| group_path(membership.group) })
    sign_in user
    get groups_path
    expect(index_group_paths).to eq(memberships.map { |membership| group_path(membership.group) })
  end

  it "appends a new join and moves a left group behind current memberships" do
    sign_in user
    patch groups_membership_order_path, params: { membership_ids: memberships.map(&:id) }
    joining = Group.create!(group_admin: owner, name: "New public club", lifecycle_status: :active, created_at: 1.year.ago)
    post group_group_memberships_path(joining)
    expect(response).to redirect_to(group_path(joining))
    get groups_path
    expect(index_group_paths).to eq(memberships.map { |membership| group_path(membership.group) } + [ group_path(joining) ])

    delete group_group_membership_path(memberships.second.group, memberships.second)

    expect(response).to redirect_to(groups_path)
    get groups_path
    expect(index_group_paths).to eq([ memberships.first, memberships.last ].map { |membership| group_path(membership.group) } + [ group_path(joining), group_path(memberships.second.group_id) ])
    get edit_groups_membership_order_path
    expect(edit_membership_ids).not_to include(memberships.second.id)
  end

  it "uses the saved order across three-card desktop pages while editing all clubs on one page" do
    4.times do |index|
      group = Group.create!(group_admin: owner, name: "Extra #{index}", lifecycle_status: :active)
      memberships << group.group_memberships.create!(user:, status: :active)
    end
    activity = owner.jjaeks.create!(group: memberships.first.group, content: "Existing recent group activity")
    sign_in user
    get edit_groups_membership_order_path
    expect(edit_membership_ids).to contain_exactly(*memberships.map(&:id))
    expect(Nokogiri::HTML(response.body).at_css("[data-controller='group-carousel']")).to be_nil
    ordered = memberships.rotate(2)
    patch groups_membership_order_path, params: { membership_ids: ordered.map(&:id) }
    get groups_path

    page = Nokogiri::HTML(response.body)
    cards = page.css("[data-group-carousel-target='card']")
    expect(cards.each_slice(3).map(&:size)).to eq([ 3, 3, 1 ])
    expect(cards.reject { |card| card.key?("hidden") }.size).to eq(3)
    expect(page.at_css("[data-group-carousel-target='position']").text.strip).to eq("1 / 3")
    expect(index_group_paths).to eq(ordered.map { |membership| group_path(membership.group) })
    expect(response.body).to include(activity.content)
  end

  %i[duplicate missing foreign pending invited ended malformed absent].each do |invalid_order|
    it "rejects #{invalid_order} IDs without changing any positions" do
      ids = memberships.map(&:id)
      case invalid_order
      when :duplicate
        ids[1] = ids.first
      when :missing
        ids.pop
      when :foreign
        ids[1] = memberships.second.group.group_memberships.find_by!(user: owner).id
      when :pending, :invited, :ended
        if invalid_order == :ended
          club = Group.create!(group_admin: owner, name: "Excluded", application_purpose: "Read")
          excluded = club.group_memberships.create!(user:, status: :active)
          club.update!(lifecycle_status: :rejected)
        else
          club = Group.create!(group_admin: owner, name: "Excluded", lifecycle_status: :active)
          excluded = club.group_memberships.create!(user:, status: invalid_order)
        end
        ids << excluded.id
      when :malformed
        ids[1] = "#{ids[1]}garbage"
      when :absent
        ids = nil
      end
      positions = GroupMembership.order(:id).pluck(:id, :position)
      sign_in user

      patch groups_membership_order_path, params: { membership_ids: ids }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("groups.membership_order.failed"))
      expect(GroupMembership.order(:id).pluck(:id, :position)).to eq(positions)
    end
  end

  %i[join leave removed].each do |change|
    it "refuses a stale editing list after a concurrent #{change}" do
      sign_in user
      get edit_groups_membership_order_path
      submitted_ids = edit_membership_ids
      if change == :join
        club = Group.create!(group_admin: owner, name: "Joined while editing", lifecycle_status: :active)
        post group_group_memberships_path(club)
      elsif change == :leave
        delete group_group_membership_path(memberships.last.group, memberships.last)
      else
        sign_in owner
        delete remove_group_group_membership_path(memberships.last.group, memberships.last)
        sign_in user
      end
      positions = user.group_memberships.order(:id).pluck(:id, :position)

      patch groups_membership_order_path, params: { membership_ids: submitted_ids }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.group_memberships.order(:id).pluck(:id, :position)).to eq(positions)
    end
  end

  it "retains MembershipScope and the existing private, pending, and inactive access boundaries" do
    pending = Group.create!(group_admin: user, name: "My opening", application_purpose: "Read together")
    inactive = memberships.first.group
    inactive.update!(lifecycle_status: :inactive, closed_at: Time.current, closure_reason: "Finished")
    memberships.second.update!(moderation_status: :activity_suspended)
    inactive.update!(operation_suspended_at: Time.current)
    inaccessible = Group.create!(group_admin: owner, name: "Not a member", group_type: :private_group, lifecycle_status: :active)
    ended = Group.create!(group_admin: user, name: "Cancelled opening", application_purpose: "Read")
    ended.update!(lifecycle_status: :cancelled)
    sign_in user
    expected_ids = memberships.map(&:id) + [ pending.group_memberships.find_by!(user:).id ]

    get edit_groups_membership_order_path
    expect(edit_membership_ids).to contain_exactly(*expected_ids)
    expect(response.body).not_to include(inaccessible.name, ended.name)
    patch groups_membership_order_path, params: { membership_ids: expected_ids }
    expect(response).to redirect_to(groups_path)
    get group_path(inaccessible)
    expect(response).to redirect_to(groups_path)
    get edit_group_path(inactive)
    expect(response).to redirect_to(root_path)
    get group_path(pending)
    expect(response).to have_http_status(:ok)
    expect(GroupPolicy.new(user, inactive).read_jjaeks?).to be(true)
    expect(GroupPolicy.new(user, inactive).create_jjaek?).to be(false)
  end
end
