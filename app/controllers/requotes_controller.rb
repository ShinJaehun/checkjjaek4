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
      .includes(:user, :book, :group, :target_user, :likes, :comments, quoted_jjaek: [ :user, :book, :group ])
      .recent

    prepare_current_reading_states_for(readable_requotes)
    @requotes = readable_requotes.map { |requote| [ requote, false ] }
    if @jjaek.user_id == current_user.id
      restricted_requotes = JjaekPolicy::RestrictedRequoteScope
        .new(current_user, Jjaek.where(quoted_jjaek_id: @jjaek.id))
        .resolve
        .select(:id, :user_id, :group_id, :quoted_jjaek_id, :created_at, :hidden_at, :deleted_at)
        .preload(:user, :group)
      @requotes.concat(restricted_requotes.map { |requote| [ requote, true ] })
      @requotes.sort_by! { |requote, _restricted| [ requote.created_at, requote.id ] }.reverse!
    end
  end
end
