require "rails_helper"

RSpec.describe "Current and past personal group lists", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "list-reader@example.com", password: "password123!") }
  let!(:owner) { User.create!(name: "Owner", email: "list-owner@example.com", password: "password123!") }
  let!(:group) { Group.create!(group_admin: owner, name: "SECRET CURRENT NAME", group_type: :private_group, lifecycle_status: :active) }
  let!(:membership) { group.group_memberships.create!(user:, status: :active) }

  before { sign_in user }

  def listed_paths
    Nokogiri::HTML(response.body).css("[data-group-grid] article h3 a").map { |link| link["href"] }
  end

  def leave_group
    delete group_group_membership_path(group, membership)
    expect(response).to redirect_to(groups_path)
  end

  def hide_group(target = group)
    patch hide_groups_membership_order_path, params: { group_id: target.id }
  end

  it "lists current groups in personal order before actual past groups, most recently ended first" do
    others = 3.times.map do |index|
      club = Group.create!(group_admin: owner, name: "Current #{index}", lifecycle_status: :active)
      club.group_memberships.create!(user:, status: :active, position: index + 1)
    end
    older = Group.create!(group_admin: owner, name: "OLD SECRET NAME", group_type: :private_group, lifecycle_status: :active)
    older.group_membership_events.create!(user:, actor: owner, event_type: :removed, created_at: 1.day.ago)
    leave_group
    own = user.jjaeks.create!(group:, content: "INACCESSIBLE PAST ACTIVITY")
    activity = owner.jjaeks.create!(group: others.first.group, content: "READABLE CURRENT ACTIVITY")

    get groups_path

    expect(listed_paths).to eq(others.map { |row| group_path(row.group) } + [ group_path(group.id), group_path(older.id) ])
    page = Nokogiri::HTML(response.body)
    expect(page.css("[data-group-carousel-target='card']").size).to eq(5)
    expect(page.at_css("[data-group-carousel-target='position']").text.strip).to eq("1 / 2")
    expect(page.at_css("[data-past-group-id='#{group.id}']").text).to include(I18n.t("groups.past_membership.statuses.left"))
    expect(page.at_css("[data-past-group-id='#{older.id}']").text).to include(I18n.t("groups.past_membership.statuses.removed"))
    expect(response.body).to include(activity.content)
    expect(response.body).to include(group.name, older.name)
    expect(response.body).not_to include(own.content)
  end

  it "does not count applications and invitations as participation" do
    leave_group
    applicants = %i[requested_to_join join_request_cancelled request_rejected invited invitation_declined invitation_revoked].map do |event_type|
      club = Group.create!(group_admin: owner, name: event_type.to_s, group_type: :private_group, lifecycle_status: :active)
      club.group_membership_events.create!(user:, actor: owner, event_type:)
      club
    end
    get groups_path
    expect(listed_paths).to eq([ group_path(group.id) ])
    applicants.each do |club|
      get group_path(club.id)
      expect(response).to redirect_to(groups_path)
      expect(response.body).not_to include("data-cleanup-")
      hide_group(club)
      expect(response).to have_http_status(:not_found)
    end
    expect(user.group_list_hidings).to be_empty
  end

  it "keeps closed, operation-suspended and activity-suspended memberships current" do
    group.update!(lifecycle_status: :inactive, closure_reason: "Finished", closed_at: Time.current)
    get groups_path
    expect(listed_paths).to eq([ group_path(group) ])
    expect(response.body).to include(I18n.t("groups.current_statuses.inactive"))
    expect(Nokogiri::HTML(response.body).css("[data-past-group-id]")).to be_empty
    membership.update!(moderation_status: :activity_suspended)
    group.update!(operation_suspended_at: Time.current)
    get groups_path
    expect(listed_paths).to eq([ group_path(group) ])
    expect(response.body).to include(I18n.t("groups.current_statuses.suspended"), I18n.t("group_memberships.moderation.statuses.activity_suspended"))
    expect(membership.reload).to be_active

    get edit_groups_membership_order_path
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-past-groups]")).to be_nil
    expect(page.css("[data-past-group-id]")).to be_empty
    expect(page.css("input[name='membership_ids[]']").map { |input| input["value"].to_i }).to eq([ membership.id ])
    expect(page.at_css("[data-field='current-status']").text).to eq(I18n.t("groups.current_statuses.suspended"))
  end

  %i[active inactive reactivation_pending suspended].each do |status|
    it "shares named past cards and badges across both screens for a #{status} group" do
      leave_group
      group.update!(name: "Renamed former club", description: "PRIVATE DESCRIPTION")
      if status.in?(%i[inactive reactivation_pending])
        group.update!(lifecycle_status: :inactive, closure_reason: "PRIVATE CLOSURE REASON", closed_at: Time.current)
        group.update!(lifecycle_status: :pending_approval) if status == :reactivation_pending
      elsif status == :suspended
        group.update!(operation_suspended_at: Time.current)
      end

      [ groups_path, edit_groups_membership_order_path ].each do |path|
        get path
        expect(response).to have_http_status(:ok)
        page = Nokogiri::HTML(response.body)
        card = page.at_css("[data-past-group-id='#{group.id}']")
        expect(card.at_css("h3").text.strip).to eq(group.name)
        expect(card.at_css("[data-group-type='private_group']").text).to eq(I18n.t("groups.types.private_group"))
        expect(card.at_css("[data-field='current-status']").text).to eq(I18n.t("groups.current_statuses.#{status}"))
        expect(card.at_css("[data-field='membership-status']").text).to eq("탈퇴함")
        expect(card["class"].split).to include("bg-stone-50", "border-stone-300")
        expect(card["class"]).not_to match(/blur|opacity/)
        expect(card.text).not_to include(owner.name, user.name, "PRIVATE DESCRIPTION", "PRIVATE CLOSURE REASON", "이전에 참여한 동아리")
        expect(card.css("img, [data-group-members], [data-field='active-member-count']")).to be_empty
        if path == edit_groups_membership_order_path
          expect(card.css("a")).to be_empty
          expect(page.at_css("[data-past-groups] h2").text).to eq("활동하지 않는 동아리")
          expect(page.css("[data-past-groups] > p").size).to eq(1)
          expect(card.at_css("form[action='#{hide_groups_membership_order_path(group_id: group.id)}']")).to be_present
        else
          expect(card.at_css("h3 a")["href"]).to eq(group_path(group.id))
        end
      end
    end
  end

  it "refuses to remove a normally active group, including forged user IDs" do
    patch hide_groups_membership_order_path, params: { group_id: group.id, user_id: owner.id }
    expect(response).to redirect_to(root_path)
    expect(GroupListHiding.count).to eq(0)
  end

  %i[left closed operation_suspended activity_suspended removed banned].each do |state|
    it "removes and restores a #{state} group without changing membership, content or audit records" do
      case state
      when :left
        leave_group
      when :closed
        group.update!(lifecycle_status: :inactive, closed_at: Time.current, closure_reason: "Finished")
      when :operation_suspended
        group.update!(operation_suspended_at: Time.current)
      when :activity_suspended
        membership.update!(moderation_status: :activity_suspended)
      when :removed
        sign_in owner
        delete remove_group_group_membership_path(group, membership)
        sign_in user
      when :banned
        GroupMemberBans::Ban.new(membership, actor: owner, public_reason: "Rules").call!
      end
      post = user.jjaeks.create!(group:, content: "PRESERVED CONTENT")
      membership_ids = group.group_memberships.ids
      event_ids = group.group_membership_events.ids
      moderation_ids = ModerationAction.ids
      owner.group_list_hidings.create!(group:)

      if state.in?(%i[left removed banned])
        get groups_path
        card = Nokogiri::HTML(response.body).at_css("[data-past-group-id='#{group.id}']")
        expect(card.text).to include(I18n.t("groups.past_membership.statuses.#{state}"))
        expect(card.text).to include(group.name)
        expect(card.text).not_to include(owner.name, I18n.t("group_memberships.statuses.active"))
        expect(card.at_css("[data-field='membership-status']").text).to eq({ left: "탈퇴함", removed: "탈퇴 처리", banned: "이용 제한" }.fetch(state))
      end

      get edit_groups_membership_order_path
      page = Nokogiri::HTML(response.body)
      button = page.at_css("form[action='#{hide_groups_membership_order_path(group_id: group.id)}']")
      expect(button["data-turbo-confirm"]).to eq(I18n.t("groups.membership_order.hide_confirmation"))
      hide_group
      expect(response).to redirect_to(edit_groups_membership_order_path)
      expect(user.group_list_hidings.exists?(group:)).to be(true)
      get groups_path
      expect(listed_paths).to be_empty
      expect(Nokogiri::HTML(response.body).at_css("a[href='#{edit_groups_membership_order_path}']")).to be_present
      get edit_groups_membership_order_path
      excluded = Nokogiri::HTML(response.body).at_css("[data-hidden-groups]")
      expect(excluded.text).to include(I18n.t("groups.membership_order.excluded"))
      expect(excluded.at_css("form[action='#{restore_groups_membership_order_path(group_id: group.id)}']")).to be_present
      if state.in?(%i[left removed banned])
        card = excluded.at_css("[data-past-group-id='#{group.id}']")
        expect(card.at_css("h3").text).to include(group.name)
        expect(card.at_css("[data-group-type='private_group']")).to be_present
        expect(card.at_css("[data-field='current-status']")).to be_present
        expect(card.css("img, a, [data-group-members], [data-field='active-member-count']")).to be_empty
      end
      patch restore_groups_membership_order_path, params: { group_id: group.id, user_id: owner.id }
      expect(response).to redirect_to(edit_groups_membership_order_path)
      expect(user.group_list_hidings.exists?(group:)).to be(false)
      expect(owner.group_list_hidings.exists?(group:)).to be(true)
      get groups_path
      expect(listed_paths.size).to eq(1)
      expect(group.group_memberships.ids).to match_array(membership_ids)
      expect(group.group_membership_events.ids).to match_array(event_ids)
      expect(ModerationAction.ids).to match_array(moderation_ids)
      expect(post.reload.content).to eq("PRESERVED CONTENT")
    end
  end

  it "sorts visible current memberships only and rejects a list made stale by hiding" do
    other = Group.create!(group_admin: owner, name: "Other", lifecycle_status: :active)
    other_membership = other.group_memberships.create!(user:, status: :active)
    membership.update!(moderation_status: :activity_suspended, position: 2)
    hide_group
    get edit_groups_membership_order_path
    ids = Nokogiri::HTML(response.body).css("input[name='membership_ids[]']").map { |input| input["value"].to_i }
    expect(ids).to eq([ other_membership.id ])
    patch groups_membership_order_path, params: { membership_ids: [ membership.id, other_membership.id ] }
    expect(response).to have_http_status(:unprocessable_content)
    expect(other_membership.reload.position).to be_nil
    patch groups_membership_order_path, params: { membership_ids: [ other_membership.id ] }
    expect(response).to redirect_to(groups_path)
    expect(membership.reload.position).to eq(2)
  end

  it "requires sign in for removing and restoring list entries" do
    sign_out user
    [ hide_groups_membership_order_path, restore_groups_membership_order_path ].each do |path|
      patch path, params: { group_id: group.id }
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
