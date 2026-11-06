class JjaeksController < ApplicationController
  include BookShowContext
  include GroupShowContext
  include HomeFeedContext
  include ProfileContext
  include CommentModerationHistory
  include RecommendationSelection

  before_action :prepare_feed_response_format, only: %i[new edit show]
  before_action :set_jjaek, only: :show
  before_action :set_editable_jjaek, only: %i[edit update]
  before_action :set_destroy_jjaek, only: :destroy
  before_action :build_new_jjaek, only: %i[new create]
  rate_limit to: 30, within: 5.minutes, by: -> { current_user.id },
             with: :jjaek_rate_limit_exceeded, only: :create

  def new
    if @share_to_group
      authorize @quoted_jjaek, :share_to_group?
    else
      authorize @jjaek, :create?
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
    prepare_attached_books
  end

  def create
    raise Pundit::NotAuthorizedError if params[:share_to_group].present? && @group.blank?
    if @group && request.path_parameters[:group_id].blank? && @quoted_jjaek.blank? && params[:book_post_destination] != "group"
      raise Pundit::NotAuthorizedError
    end
    authorize target_user, :write_jjaek? if @group.blank? && target_user.present?
    attributes = jjaek_params.slice(:content, :visibility)
    attributes = attributes.except(:visibility) if @group.present? || @jjaek.profile_conversation?
    @jjaek.assign_attributes(attributes)

    attempts = 0
    saved = begin
      if @group
        @group.with_lock do
          authorize @group, :create_jjaek?
          if @quoted_jjaek && Jjaek.exists?(user: current_user, group: @group, quoted_jjaek: @quoted_jjaek)
            @jjaek.errors.add(:quoted_jjaek_id, :taken)
            false
          else
            authorize @jjaek, :create?
            @jjaek.save
          end
        end
      else
        authorize @jjaek, :create?
        @jjaek.save
      end
    rescue ActiveRecord::RecordNotUnique => error
      if params.key?(:selected_books) && attempts.zero? && error.message.match?(/index_books_on_(canonical_isbn|external_url)_unique/)
        attempts += 1
        build_new_jjaek
        return if performed?
        @jjaek.assign_attributes(attributes)
        retry
      end
      if @group && @quoted_jjaek
        @jjaek.errors.add(:quoted_jjaek_id, :taken)
      else
        @jjaek.errors.add(:base, t("book_search.errors.identity_conflict"))
      end
      false
    end

    if saved
      clear_recommendation_selection if @selected_book_keys
      notify_jjaek_created
      redirect_to create_success_path, notice: t("jjaeks.notices.created"), status: :see_other
    else
      render_failed_create
    end
  end

  def update
    updated = if @jjaek.group
      @jjaek.group.with_lock do
        authorize @jjaek, :update?
        save_jjaek_update
      end
    else
      save_jjaek_update
    end

    if updated
      clear_recommendation_selection if @selected_book_keys
      redirect_to jjaek_path(@jjaek, post_return_params), notice: t("jjaeks.notices.updated"), status: :see_other
    else
      render :edit, formats: :html, status: :unprocessable_content
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

  def prepare_attached_books
    @selected_books = @jjaek.attached_books.to_a
    @selected_book_keys = @selected_books.map { |book| book.id.to_s }
  end

  def save_jjaek_update
    attributes = update_jjaek_params
    if params.key?(:selected_books)
      valid = prepare_recommendation_selection(preserve_on_error: true)
      if !valid || (@jjaek.requote? && @selected_books.any?)
        @jjaek.assign_attributes(attributes)
        @jjaek.errors.add(:base, t("recommendations.invalid_selection"))
        return false
      end
    else
      prepare_attached_books
    end

    updated = @jjaek.with_lock do
      authorize @jjaek, :update?
      if params.key?(:selected_books) && !@jjaek.requote?
        @jjaek.update_attached_books(books: @selected_books, attributes:)
      else
        @jjaek.update_attached_books(attributes:)
      end
    end
    @jjaek.assign_attributes(attributes) unless updated
    updated
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
    @group = @jjaek.group
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
    raise Pundit::NotAuthorizedError if @group.present? && jjaek_target_user_id.present?
    @quoted_jjaek = find_quoted_jjaek
    return if performed?
    raise Pundit::NotAuthorizedError if params[:share_to_group].present? && @quoted_jjaek.blank?
    @share_to_group = @quoted_jjaek.present? && @quoted_jjaek.group_id.blank? &&
      (params[:share_to_group].present? || @group.present?)
    @available_share_groups = policy(@quoted_jjaek).group_share_destinations if @share_to_group
    if @group && @quoted_jjaek
      expected_group = request.path_parameters[:group_id].present? ? @group.id : nil
      raise Pundit::NotAuthorizedError unless @quoted_jjaek.group_id == expected_group
    end
    @book = find_jjaek_book unless @quoted_jjaek.present?
    raise Pundit::NotAuthorizedError if @quoted_jjaek.present? && @group.blank? && jjaek_book_id.present?
    @jjaek_visibility_options = jjaek_visibility_options_for(@quoted_jjaek)
    @jjaek = Jjaek.new(user: current_user, group: @group, quoted_jjaek: @quoted_jjaek,
      target_user: target_user, visibility: target_user.present? ? :book_friends : default_jjaek_visibility_for(@quoted_jjaek))

    valid_selection = true
    if params.key?(:selected_books)
      valid_selection = prepare_recommendation_selection(preserve_on_error: true)
      if @book && !@selected_books.any? { |book| book.id == @book.id }
        raise Pundit::NotAuthorizedError
      end
    else
      @selected_books = @book ? [@book] : []
      @selected_book_keys = @selected_books.map { |book| book.id.to_s }
    end
    @selected_books.each_with_index { |book, position| @jjaek.jjaek_recommendations.build(book:, position:) }
    if !valid_selection || (@jjaek.requote? && @selected_books.any?)
      authorize @jjaek, :create?
      @jjaek.assign_attributes(jjaek_params.slice(:content, :visibility)) if action_name == "create"
      @jjaek.errors.add(:base, t("recommendations.invalid_selection"))
      render_failed_create
    end
  end

  def render_failed_create(status: :unprocessable_content)
    return render(:new, formats: :html, status:) if @quoted_jjaek.present? || action_name == "new"

    @book ||= book_composer_context
    if @book.present?
      @bookshelf_entry = current_user.bookshelf_entries.find_by(book: @book)
      @sticker_definitions = StickerDefinition.alphabetical
      prepare_book_show_read_context
      render "books/show", formats: :html, status:
    elsif @group.present?
      prepare_group_show_context
      render "groups/show", formats: :html, status:
    elsif target_user.present?
      @user = target_user
      authorize @user, :show?
      prepare_profile_context
      @profile_jjaek = @jjaek
      render "users/show", formats: :html, status:
    else
      prepare_home_feed
      render "homes/show", formats: :html, status:
    end
  end

  def target_user
    return if jjaek_target_user_id.blank?

    raise Pundit::NotAuthorizedError unless jjaek_target_user_id.to_s.match?(/\A[1-9]\d*\z/)
    @target_user ||= User.find(jjaek_target_user_id)
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
    # This is a return destination, never an attachment or posting-context input.
    if (book = book_composer_context)
      return book_path(book, group_id: @jjaek.group_id,
        return_to: view_context.validated_jjaek_return_path(params[:return_to]))
    end
    return group_path(@group) if @group.present?

    target_user.present? ? root_path : jjaek_path(@jjaek, post_return_params)
  end

  def book_composer_context
    return if @jjaek.requote? || @jjaek.profile_conversation?
    return unless params[:book_context_id].to_s.match?(/\A[1-9]\d*\z/)

    book = Book.find_by(id: params[:book_context_id])
    book if book && policy(book).show?
  end

  def find_jjaek_group
    path_group_id = request.path_parameters[:group_id].to_s.split("-", 2).first.presence
    form_group_id = params.dig(:jjaek, :group_id)
    quoting = params[:quoted_jjaek_id].present? || params.dig(:jjaek, :quoted_jjaek_id).present?
    if quoting && path_group_id.present? && form_group_id.present? &&
        path_group_id.to_s != form_group_id.to_s
      raise Pundit::NotAuthorizedError
    end

    group_id = path_group_id || form_group_id || (params[:group_id] unless action_name == "create")
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
    return if jjaek_book_id.blank?
    raise Pundit::NotAuthorizedError unless jjaek_book_id.to_s.match?(/\A[1-9]\d*\z/)
    form_id = params.dig(:jjaek, :book_id)
    if params[:book_id].present? && form_id.present? && params[:book_id].to_s != form_id.to_s
      raise Pundit::NotAuthorizedError
    end
    Book.find(jjaek_book_id)
  end

  def find_quoted_jjaek
    return unless jjaek_quoted_id.present?

    quoted_jjaek = policy_scope(Jjaek).find_by(id: jjaek_quoted_id)
    return quoted_jjaek if quoted_jjaek

    redirect_to root_path, alert: t("jjaeks.alerts.requote_source_unavailable")
    nil
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
    params.require(:jjaek).permit(:book_id, :group_id, :content, :visibility, :quoted_jjaek_id, :target_user_id)
  end

  def update_jjaek_params
    return jjaek_params.slice(:content) if @jjaek.group.present? || @jjaek.profile_conversation?

    jjaek_params.slice(:content, :visibility)
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
