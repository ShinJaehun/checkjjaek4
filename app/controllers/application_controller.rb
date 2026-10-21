class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :reject_suspended_session!
  before_action :authenticate_user!, unless: :devise_controller?
  before_action :configure_permitted_parameters, if: :devise_controller?

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  rescue_from FeedPage::InvalidCursor, with: -> { head :bad_request }

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :name, :handle ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :name ])
  end

  def after_sign_in_path_for(_resource)
    root_path
  end

  def after_sign_out_path_for(_resource_or_scope)
    new_user_session_path
  end

  private

  def feed_page_request?
    request.get? && request.format.turbo_stream? &&
      request.headers["X-Feed-Pagination"] == "true" && params[:cursor].present?
  end

  def prepare_feed_response_format
    return unless request.format.turbo_stream?
    return if feed_page_request?

    # Turbo can retain its stream Accept header while following a form redirect.
    request.format = :html
    self.formats = [ :html ]
  end

  def render_feed_page(context:, next_url:)
    render "feeds/page", locals: { page: @feed_page, context:, next_url:, profile_user: @user, book: @book }
  end

  def authentication_rate_limit_exceeded
    self.resource = resource_class.new
    request.env["devise.allow_params_authentication"] = false
    flash.now[:alert] = authentication_rate_limit_message
    render :new, formats: :html, status: :too_many_requests
  end

  def authentication_rate_limit_message
    t("auth.alerts.rate_limited")
  end

  def render_content_rate_limit_flash(message)
    flash.now[:alert] = message
    render turbo_stream: turbo_stream.update("flash-messages", partial: "shared/flash"), status: :too_many_requests
  end

  def reject_suspended_session!
    return unless current_user&.suspended?

    reason = current_user.current_suspension_action&.public_reason
    reason = User.suspension_reason_label(reason) if reason.present?
    message = reason.present? ? t("auth.alerts.suspended", reason:) : t("auth.alerts.suspended_fallback")
    sign_out current_user
    redirect_to new_user_session_path, alert: message, status: :see_other
  end

  def prepare_book_show_read_context(feed_only: false)
    @bookshelves = current_user.bookshelves.default_first unless feed_only
    if @bookshelf_entry.present? && !feed_only
      @book_post_groups = policy_scope(Group, policy_scope_class: GroupPolicy::CreateJjaekScope)
        .order(:name, :id).select { |group| policy(group).create_jjaek? }
    end
    book_jjaeks = @book.jjaeks.includes(:book, :group, :likes, :comments,
      user: { avatar_attachment: :blob }, target_user: { avatar_attachment: :blob })
    @jjaeks = if @group.present? && @bookshelf_entry.present?
      policy_scope(book_jjaeks, policy_scope_class: JjaekPolicy::GroupContentScope).where(group: @group)
    else
      policy_scope(book_jjaeks, policy_scope_class: JjaekPolicy::BookScope)
    end
    @feed_page = FeedPage.new(jjaeks: @jjaeks.where(quoted_jjaek_id: nil), cursor: params[:cursor])
    if @feed_page.next_cursor
      @feed_next_url = book_path(@book, group_id: @group&.id,
        return_to: view_context.validated_jjaek_return_path(params[:return_to]), cursor: @feed_page.next_cursor)
    end
    @jjaeks = @feed_page.items
    prepare_current_reading_states_for(@jjaeks)
    prepare_book_friend_activities unless feed_only
    prepare_visible_requote_counts_for(@jjaeks + Array(@book_friend_activities).grep(Jjaek))
  end

  def prepare_book_friend_activities
    friend_ids = BookFriendship.connected_ids_for(current_user)
    activities = policy_scope(BookActivity.where(book: @book), policy_scope_class: BookActivityPolicy::BookFriendScope)
      .includes(:book, user: { avatar_attachment: :blob })
      .order(created_at: :desc, id: :desc)
      .limit(3)
      .to_a
    jjaeks = policy_scope(
      @book.jjaeks.where(user_id: friend_ids, group_id: nil, hidden_at: nil, deleted_at: nil),
      policy_scope_class: JjaekPolicy::BookScope
    ).includes(:book, :likes, :comments, user: { avatar_attachment: :blob },
      quoted_jjaek: [ { user: { avatar_attachment: :blob } }, :book, :group ])
      .order(created_at: :desc, id: :desc).limit(3).to_a

    @book_friend_activities = (activities + jjaeks)
      .sort_by { |item| [ -item.created_at.to_r, item.is_a?(BookActivity) ? 0 : 1, -item.id ] }
      .first(3)

    sticker_ids = @book_friend_activities.grep(BookActivity).flat_map do |activity|
      metadata = activity.metadata
      Array(metadata["added_sticker_definition_ids"]) + Array(metadata["removed_sticker_definition_ids"]) +
        Array(metadata["sticker_definition_ids"]) + Array(metadata["sticker_definition_id"])
    end
    @book_friend_sticker_definitions = sticker_ids.empty? ? {} : StickerDefinition.where(id: sticker_ids).index_by(&:id)
  end

  def prepare_current_reading_states_for(jjaeks)
    records = Array(jjaeks).select { |jjaek| jjaek.book_id.present? && !jjaek.deleted? }
    @current_reading_states ||= {}
    return if records.empty?

    entries = policy_scope(BookshelfEntry, policy_scope_class: BookshelfEntryPolicy::ReadingStateScope)
      .where(user_id: records.map(&:user_id), book_id: records.map(&:book_id))
      .includes(:sticker_definitions)
    entries.each do |entry|
      @current_reading_states[[ entry.user_id, entry.book_id ]] = entry
    end
  end

  def prepare_visible_requote_counts_for(jjaeks)
    records = Array(jjaeks)
    original_ids = records.reject(&:requote?).filter_map(&:id)

    @visible_requote_counts_by_jjaek_id = {}
    return if original_ids.empty?

    @visible_requote_counts_by_jjaek_id = policy_scope(Jjaek)
      .where(quoted_jjaek_id: original_ids)
      .group(:quoted_jjaek_id).count
    return unless current_user

    own_original_ids = records.filter_map do |jjaek|
      jjaek.id if jjaek.user_id == current_user.id && policy(jjaek).view_requotes?
    end
    return if own_original_ids.empty?

    restricted_counts = JjaekPolicy::RestrictedRequoteScope
      .new(current_user, Jjaek.where(quoted_jjaek_id: own_original_ids))
      .resolve.group(:quoted_jjaek_id).count
    restricted_counts.each do |original_id, count|
      @visible_requote_counts_by_jjaek_id[original_id] = @visible_requote_counts_by_jjaek_id.fetch(original_id, 0) + count
    end
  end

  def user_not_authorized
    redirect_back fallback_location: root_path, alert: t("auth.alerts.not_authorized")
  end
end
