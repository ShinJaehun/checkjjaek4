class JjaeksController < ApplicationController
  include BookShowContext
  include CommentModerationHistory
  include GroupShowContext
  include HomeFeedContext
  include ProfileContext
  include BookSearchResults
  include RecommendationSelection

  before_action :set_jjaek, only: :show
  before_action :set_editable_jjaek, only: %i[edit update]
  before_action :set_destroy_jjaek, only: :destroy
  before_action :build_new_jjaek, only: %i[new create]
  rate_limit to: 30, within: 5.minutes, by: -> { current_user.id },
             with: :jjaek_rate_limit_exceeded, only: :create

  def new
    if @jjaek.recommendation?
      @recommendation_context = true
      return render :recommendation
    end

    raise ActiveRecord::RecordNotFound if params[:share_to_group].present? && !@share_to_group

    if @group.present?
      raise ActiveRecord::RecordNotFound unless @quoted_jjaek&.group_id == @group.id
    elsif @share_to_group
      authorize @quoted_jjaek, :share_to_group?
    end
  end

  def show
    if @profile_reaction_cleanup
      @cleanup_comments = @jjaek.comments.where(user: current_user).order(:created_at, :id)
      @cleanup_like = @jjaek.likes.find_by(user: current_user)
      return render :reaction_cleanup
    end

    @current_hide_action = @jjaek.current_hide_action if @jjaek.hidden?
    if policy(@jjaek).view_admin_inventory?
      @moderation_actions = @jjaek.moderation_actions
        .where(action_type: %i[hide restore])
        .includes(:actor)
        .order(created_at: :asc, id: :asc)
    end
    if policy(@jjaek).view_group_moderation_history?
      @group_moderation_actions = @jjaek.moderation_actions
        .where(action_type: %i[hide restore], moderation_authority: "group")
        .includes(:actor)
        .order(created_at: :asc, id: :asc)
    end
    if policy(@jjaek).view_deleted_tombstone? && !policy(@jjaek).view_admin_inventory?
      prepare_comments
      return render :hidden
    end
    if policy(@jjaek).view_hidden_placeholder?
      prepare_comments
      return render :hidden
    end
   if @jjaek.hidden? && !policy(@jjaek).view_admin_inventory?
     prepare_comments
     return render :hidden
   end

    prepare_comments
    prepare_current_reading_states_for([ @jjaek ])
    prepare_visible_requote_counts_for([ @jjaek ])
  end

  def edit
    return unless @jjaek.recommendation?

    prepare_recommendation_edit
    return render :recommendation if turbo_frame_request?

    @recommendation_edit_start = true
    render "book_searches/show"
  end

  def create
    authorize target_user, :write_jjaek? if @group.blank? && target_user.present?
    raise Pundit::NotAuthorizedError if params[:share_to_group].present? && @group.blank?
    if @group.present? && request.path_parameters[:group_id].blank? && @quoted_jjaek.blank? &&
        params[:book_post_destination] != "group"
      raise Pundit::NotAuthorizedError
    end
    if @group.present? && @quoted_jjaek.present?
      nested_group_route = request.path_parameters[:group_id].present?
      valid_source = nested_group_route ? @quoted_jjaek.group_id == @group.id : @quoted_jjaek.group_id.nil?
      raise Pundit::NotAuthorizedError unless valid_source
    end

    attributes = jjaek_params
    attributes = attributes.slice(:content, :visibility) if @jjaek.recommendation?
    attributes = attributes.except(:book_id, :visibility, :target_user_id) if @group.present? && @quoted_jjaek.present?
    attributes = attributes.except(:visibility) if @jjaek.profile_conversation?
    @jjaek.assign_attributes(attributes)

    recommendation_save_attempts = 0
    saved = begin
      if @group
        @group.with_lock do
          if group_requote_already_exists?
            @jjaek.errors.add(:quoted_jjaek_id, :taken)
            false
          else
            authorize @jjaek
            @jjaek.save
          end
        end
      else
        authorize @jjaek
        @jjaek.save
      end
    rescue ActiveRecord::RecordNotUnique => error
      if @jjaek.recommendation?
        if recommendation_save_attempts.zero? && error.message.match?(/index_books_on_(canonical_isbn|external_url)_unique/)
          recommendation_save_attempts += 1
          build_recommendation_jjaek
          return if performed?

          @jjaek.assign_attributes(attributes)
          retry
        end
        @jjaek.errors.add(:base, t("book_search.errors.identity_conflict"))
      else
        raise unless @jjaek.quoted_jjaek_id.present?

        @jjaek.errors.add(:quoted_jjaek_id, :taken)
      end
      false
    end

    if saved
      clear_recommendation_selection if @jjaek.recommendation?
      notify_jjaek_created
      if @jjaek.recommendation? && request.format.turbo_stream?
        flash[:notice] = t("jjaeks.notices.created")
        return render turbo_stream: turbo_stream.append("recommendation_composer",
          view_context.tag.span(data: { recommendation_composer_target: "completed", location: create_success_path }))
      end
      redirect_to create_success_path, notice: t("jjaeks.notices.created")
    else
      render_failed_create
    end
  end

  def update
    updated = if @jjaek.group
      @jjaek.group.with_lock do
        authorize @jjaek
        save_jjaek_update
      end
    else
      save_jjaek_update
    end

    if updated
      clear_recommendation_selection if @jjaek.recommendation?
      destination = jjaek_path(@jjaek, post_return_params)
      if @jjaek.recommendation? && request.format.turbo_stream?
        flash[:notice] = t("jjaeks.notices.updated")
        return render turbo_stream: turbo_stream.append("recommendation_composer",
          view_context.tag.span(data: { recommendation_composer_target: "completed", location: destination }))
      end
      redirect_to destination, notice: t("jjaeks.notices.updated")
    elsif @jjaek.recommendation?
      @recommendation_context = true
      @recommendation_step = "writing"
      prepare_book_search_results
      if request.format.turbo_stream?
        return render turbo_stream: turbo_stream.update("recommendation_composer", partial: "jjaeks/recommendation_panel"), status: :unprocessable_content
      end
      @recommendation_edit_start = true
      render "book_searches/show", formats: :html, status: :unprocessable_content
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    group = @jjaek.group
    @jjaek.destroy_or_tombstone!
    if group.present? && policy(group).cleanup_content?
      destination = params[:return_to] == "group_restricted_content" ? group_path(group.id) : groups_path
      redirect_to destination, notice: t("jjaeks.notices.destroyed"), status: :see_other
      return
    end
    destination = view_context.jjaek_detail_return_params(@jjaek)[:return_to]
    redirect_to destination || destroy_success_path(group), notice: t("jjaeks.notices.destroyed"), status: :see_other
  end

  private

  def prepare_recommendation_edit
    @editing_recommendation = @jjaek
    @group = @jjaek.group
    @recommendation_context = true
    @recommendation_step = "writing"
    if params.key?(:selected_books)
      prepare_recommendation_selection(redirect_on_error: false, preserve_on_error: true)
    else
      @selected_books = @jjaek.recommended_books.to_a
      @selected_book_keys = @selected_books.map { |book| book.id.to_s }
    end
    prepare_book_search_results
  end

  def save_jjaek_update
    return @jjaek.update(update_jjaek_params) unless @jjaek.recommendation?

    @editing_recommendation = @jjaek
    @group = @jjaek.group
    valid_selection = if params.key?(:selected_books)
      prepare_recommendation_selection(redirect_on_error: false, enforce_limit: false, preserve_on_error: true)
    else
      @selected_books = @jjaek.recommended_books.to_a
      @selected_book_keys = @selected_books.map { |book| book.id.to_s }
      true
    end
    unless valid_selection
      @jjaek.assign_attributes(update_jjaek_params)
      @jjaek.errors.add(:base, t("recommendations.invalid_selection"))
      return false
    end

    @jjaek.with_lock do
      authorize @jjaek, :update?
      @jjaek.update_recommendation_books(books: @selected_books, attributes: update_jjaek_params)
    end
  end

  def jjaek_rate_limit_exceeded
    message = t("jjaeks.alerts.rate_limited")
    respond_to do |format|
      format.turbo_stream { render_content_rate_limit_flash(message) }
      format.html do
        @jjaek.assign_attributes(jjaek_params)
        flash.now[:alert] = message
        render_failed_create(status: :too_many_requests)
      end
    end
  end

  def set_jjaek
    @jjaek = Jjaek.find(params[:id])

    unless policy(@jjaek).show?
      if policy(@jjaek).cleanup_profile_reactions?
        authorize @jjaek, :cleanup_profile_reactions?
        @profile_reaction_cleanup = true
        return
      end
      raise ActiveRecord::RecordNotFound if @jjaek.group_id.present?

      redirect_to root_path, alert: t("jjaeks.alerts.not_found_or_inaccessible")
      return
    end
    authorize @jjaek
  end

  def set_editable_jjaek
    @jjaek = Jjaek.find_by(id: params[:id])

    unless @jjaek
      redirect_to root_path, alert: t("jjaeks.alerts.not_found_or_inaccessible")
      return
    end

    if @jjaek.group_id.present? && !policy(@jjaek).show?
      raise ActiveRecord::RecordNotFound
    end
    authorize @jjaek
  end

  def set_destroy_jjaek
    @jjaek = Jjaek.find_by(id: params[:id])
    unless @jjaek
      redirect_to root_path, alert: t("jjaeks.alerts.not_found_or_inaccessible"), status: :see_other
      return
    end

    authorize @jjaek, :destroy?
  end

  def build_new_jjaek
    validate_book_post_destination!
    @group = find_jjaek_group
    return build_recommendation_jjaek if recommendation_context?

    @quoted_jjaek = find_quoted_jjaek
    return if performed?

    @share_to_group = @quoted_jjaek.present? && @quoted_jjaek.group_id.blank? &&
      (params[:share_to_group].present? || @group.present?)
    @available_share_groups = policy(@quoted_jjaek).group_share_destinations if @share_to_group
    @book = find_jjaek_book unless (@group.present? && @quoted_jjaek.present?) || @share_to_group
    @jjaek_visibility_options = jjaek_visibility_options_for(@quoted_jjaek)
    @jjaek = Jjaek.new(
      user: current_user,
      book: @book,
      group: @group,
      quoted_jjaek: @quoted_jjaek,
      target_user: @group.present? ? nil : target_user,
      visibility: @group.blank? && target_user.present? ? :book_friends : default_jjaek_visibility_for(@quoted_jjaek)
    )
    authorize @jjaek if action_name == "new" && !@share_to_group
  end

  def build_recommendation_jjaek
    raise Pundit::NotAuthorizedError if jjaek_book_id.present? || jjaek_quoted_id.present? ||
      jjaek_target_user_id.present? || params[:share_to_group].present? || params.key?(:book_post_destination)
    selection_valid = prepare_recommendation_selection(
      redirect_on_error: action_name != "create", enforce_limit: action_name != "create"
    )
    return if performed?

    @query = params[:query].to_s.strip
    @page = Integer(params[:page], exception: false)
    @jjaek = Jjaek.new(user: current_user, group: @group, recommendation: true)
    @selected_books.each_with_index do |book, position|
      @jjaek.jjaek_recommendations.build(book:, position:)
    end
    authorize @jjaek, :create?
    if action_name == "create" && !selection_valid
      @jjaek.assign_attributes(jjaek_params.slice(:content, :visibility))
      render_failed_create
    end
  end

  def render_failed_create(status: :unprocessable_content)
    if @jjaek.recommendation?
      @recommendation_context = true
      @recommendation_step = "writing"
      if request.format.turbo_stream?
        return render turbo_stream: turbo_stream.update("recommendation_composer", partial: "jjaeks/recommendation_panel"), status:
      end
      return render(:recommendation, formats: :html, status:)
    end

    if @group.present? && @quoted_jjaek.present?
      @available_share_groups = policy(@quoted_jjaek).group_share_destinations if @share_to_group
      return render :new, status:
    end
    return render_group_book_create_failure(status:) if @group.present? && @book.present?
    return render_group_create_failure(status:) if @group.present?
    return render_book_create_failure(status:) if @book.present?
    return render(:new, status:) if @quoted_jjaek.present?
    return render_profile_create_failure(status:) if render_profile_create_failure?

    render_home_create_failure(status:)
  end

  def target_user
    return if jjaek_target_user_id.blank?

    @target_user ||= User.find(jjaek_target_user_id)
  end

  def prepare_user_context(user)
    @user = user
    authorize @user, :show?
    prepare_profile_context
    @profile_jjaek = @jjaek
  end

  def prepare_comments
    @comment = Comment.new(jjaek: @jjaek)
    @comments = @jjaek.comments.includes(user: { avatar_attachment: :blob }).order(created_at: :asc)
    prepare_comment_moderation_histories(@comments)
    prepare_jjaek_card_summaries_for([ @jjaek ])
  end

  def post_return_params
    view_context.jjaek_detail_return_params(@jjaek)
  end

  def create_success_path
    return view_context.recommendation_origin_path if @jjaek.recommendation?
    return group_path(@group) if @group.present?

    target_user.present? ? root_path : jjaek_path(@jjaek, post_return_params)
  end

  def find_jjaek_group
    path_group_id = request.path_parameters[:group_id].to_s.split("-", 2).first.presence
    form_group_id = params.dig(:jjaek, :group_id)
    quoting = params[:quoted_jjaek_id].present? ||
      params.dig(:jjaek, :quoted_jjaek_id).present?
    if quoting && path_group_id.present? && form_group_id.present? &&
        path_group_id.to_s != form_group_id.to_s
      raise Pundit::NotAuthorizedError
    end

    group_id = path_group_id || (form_group_id if action_name == "create")
    return if group_id.blank?
    raise Pundit::NotAuthorizedError unless group_id.to_s.match?(/\A[1-9]\d*\z/)

    if params[:book_post_destination] == "group"
      policy_scope(Group, policy_scope_class: GroupPolicy::CreateJjaekScope).find(group_id)
    else
      policy_scope(Group).find(group_id)
    end
  end

  def validate_book_post_destination!
    return unless params.key?(:book_post_destination)

    destination = params[:book_post_destination]
    valid_book_post = action_name == "create" && params.dig(:jjaek, :book_id).present? &&
      params[:quoted_jjaek_id].blank? && params.dig(:jjaek, :quoted_jjaek_id).blank? &&
      params[:share_to_group].blank? && jjaek_target_user_id.blank?
    raise Pundit::NotAuthorizedError unless valid_book_post && destination.in?(%w[personal group])

    path_group_id = request.path_parameters[:group_id].to_s.split("-", 2).first.presence
    form_group_id = params.dig(:jjaek, :group_id)
    if destination == "personal"
      raise Pundit::NotAuthorizedError if path_group_id.present? || form_group_id.present?
    else
      raise Pundit::NotAuthorizedError if form_group_id.blank?
      if path_group_id.present? && path_group_id.to_s != form_group_id.to_s
        raise Pundit::NotAuthorizedError
      end
    end
  end

  def find_jjaek_book
    Book.find(jjaek_book_id) if jjaek_book_id.present?
  end

  def find_quoted_jjaek
    return unless jjaek_quoted_id.present?

    quoted_jjaek = policy_scope(Jjaek).find_by(id: jjaek_quoted_id)
    return quoted_jjaek if quoted_jjaek

    redirect_to root_path, alert: t("jjaeks.alerts.requote_source_unavailable")
    nil
  end

  def render_book_create_failure(status:)
    @bookshelf_entry = current_user.bookshelf_entries.find_by(book: @book) ||
      BookshelfEntry.new(user: current_user, book: @book)
    authorize @bookshelf_entry
    @sticker_definitions = StickerDefinition.alphabetical
    prepare_book_show_read_context
    render "books/show", status:
  end

  def render_group_book_create_failure(status:)
    @bookshelf_entry = current_user.bookshelf_entries.find_by(book: @book)
    @sticker_definitions = StickerDefinition.alphabetical
    prepare_book_show_read_context
    render "books/show", status:
  end

  def render_group_create_failure(status:)
    prepare_group_show_context
    render "groups/show", status:
  end

  def render_profile_create_failure?
    target_user.present? && Pundit.policy!(current_user, target_user).write_jjaek?
  end

  def render_profile_create_failure(status:)
    prepare_user_context(target_user)
    render "users/show", status:
  end

  def render_home_create_failure(status:)
    prepare_home_feed
    render "homes/show", status:
  end

  def jjaek_book_id
    params.dig(:jjaek, :book_id) || params[:book_id]
  end

  def jjaek_quoted_id
    form_id = params.dig(:jjaek, :quoted_jjaek_id)
    url_id = params[:quoted_jjaek_id]
    if url_id.present? && params[:jjaek]&.key?(:quoted_jjaek_id) && form_id.to_s != url_id.to_s
      raise Pundit::NotAuthorizedError
    end

    quoted_id = form_id || url_id
    raise Pundit::NotAuthorizedError if quoted_id.present? && !quoted_id.to_s.match?(/\A[1-9]\d*\z/)

    quoted_id
  end

  def jjaek_target_user_id
    params.dig(:jjaek, :target_user_id)
  end

  def jjaek_params
    params.require(:jjaek).permit(:book_id, :content, :visibility, :quoted_jjaek_id, :target_user_id)
  end

  def group_requote_already_exists?
    @jjaek.quoted_jjaek_id.present? &&
      Jjaek.exists?(user_id: current_user.id, quoted_jjaek_id: @jjaek.quoted_jjaek_id, group_id: @group.id)
  end

  def update_jjaek_params
    return jjaek_params.slice(:content) if @jjaek.group_id.present? || @jjaek.profile_conversation?

    jjaek_params.except(:book_id, :group_id, :quoted_jjaek_id, :target_user_id)
  end

  def destroy_success_path(group)
    return root_path if group.blank?
    return group_path(group) if policy(group).show?

    groups_path
  end

  def jjaek_visibility_options_for(quoted_jjaek)
    return Jjaek.visibilities.keys unless quoted_jjaek&.book_friends?

    %w[book_friends private_jjaek]
  end

  def default_jjaek_visibility_for(quoted_jjaek)
    return :book_friends if quoted_jjaek&.book_friends?

    :public_jjaek
  end

  def notify_jjaek_created
    Notification.notify_profile_jjaek_created(@jjaek)
    Notification.notify_requote_created(@jjaek) if @jjaek.requote?
  end
end
