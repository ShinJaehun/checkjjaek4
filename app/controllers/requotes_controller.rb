class RequotesController < ApplicationController
  def index
    @jjaek = Jjaek.find_by(id: params[:jjaek_id])
    if @jjaek.nil? || (@jjaek.group_id.nil? && !policy(@jjaek).view_requotes?)
      redirect_to root_path, alert: t("jjaeks.alerts.not_found_or_inaccessible")
      return
    end

    authorize @jjaek, :view_requotes?

    readable_requotes = policy_scope(Jjaek)
      .where(quoted_jjaek_id: @jjaek.id)
    restricted_requotes = if @jjaek.user_id == current_user.id
      JjaekPolicy::RestrictedRequoteScope
        .new(current_user, Jjaek.where(quoted_jjaek_id: @jjaek.id))
        .resolve
    else
      Jjaek.none
    end

    combined = Jjaek.where(id: readable_requotes.select(:id))
      .or(Jjaek.where(id: restricted_requotes.select(:id)))
    @total_pages = [ (combined.count.to_f / 20).ceil, 1 ].max
    requested_page = Integer(params[:page].to_s, 10, exception: false).to_i
    @page = requested_page.clamp(1, @total_pages)
    page_ids = combined.order(created_at: :desc, id: :desc)
      .limit(20).offset((@page - 1) * 20).pluck(:id)

    readable_page = readable_requotes.where(id: page_ids)
      .includes(:book, :group, :likes, :comments, :moderation_actions,
        user: { avatar_attachment: :blob }, target_user: { avatar_attachment: :blob },
        quoted_jjaek: [ { user: { avatar_attachment: :blob } }, :book, :group ]).to_a
    restricted_page = restricted_requotes.where(id: page_ids)
      .select(:id, :user_id, :group_id, :quoted_jjaek_id, :created_at, :hidden_at, :deleted_at)
      .preload(:group, user: { avatar_attachment: :blob }).to_a
    prepare_current_reading_states_for(readable_page)
    prepare_visible_requote_counts_for(readable_page)
    cards = readable_page.to_h { |requote| [ requote.id, [ requote, false ] ] }
      .merge(restricted_page.to_h { |requote| [ requote.id, [ requote, true ] ] })
    @requotes = page_ids.filter_map { |id| cards[id] }
  end
end
