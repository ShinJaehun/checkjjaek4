class CommentsController < ApplicationController
  COMMENTS_CONTEXTS = %w[detail home profile book group].freeze

  before_action :set_readable_jjaek, except: :destroy
  before_action :set_destroy_jjaek, only: :destroy
  before_action :set_comments_context, only: %i[index create update destroy]
  before_action :set_comment, only: %i[update destroy]

  def index
    @comments_panel_closed = inline_comments_context? && params[:panel_state] == "closed"
    prepare_comments_panel(comment: Comment.new(jjaek: @jjaek))

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to jjaek_path(@jjaek, anchor: helpers.comments_panel_dom_id(@jjaek)) }
    end
  end

  def create
    @comment = Comment.new(comment_params.merge(jjaek: @jjaek, user: current_user))
    authorize @comment

    saved = if @jjaek.group
      @jjaek.group.with_lock do
        authorize @comment
        @comment.save
      end
    else
      @comment.save
    end

    if saved
      Notification.notify_comment_created(@comment)
      @jjaek.reload
      prepare_comments_panel(comment: Comment.new(jjaek: @jjaek))

      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = t("comments.notices.created") }
        format.html { redirect_to jjaek_path(@jjaek), notice: t("comments.notices.created") }
      end
    else
      prepare_comments_panel(comment: @comment)
      respond_to do |format|
        format.turbo_stream { render :create, status: :unprocessable_content }
        format.html do
          prepare_visible_requote_counts_for([ @jjaek ])
          render "jjaeks/show", status: :unprocessable_content
        end
      end
    end
  end

  def update
    authorize @comment

    updated = if @jjaek.group
      @jjaek.group.with_lock do
        authorize @comment
        @comment.update(comment_params)
      end
    else
      @comment.update(comment_params)
    end

    if updated
      prepare_comments_panel(comment: Comment.new(jjaek: @jjaek))
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = t("comments.notices.updated") }
        format.html { redirect_to jjaek_path(@jjaek), notice: t("comments.notices.updated") }
      end
    else
      prepare_comments_panel(comment: Comment.new(jjaek: @jjaek), editing_comment: @comment)
      respond_to do |format|
        format.turbo_stream { render :update, status: :unprocessable_content }
        format.html do
          prepare_visible_requote_counts_for([ @jjaek ])
          render "jjaeks/show", status: :unprocessable_content
        end
      end
    end
  end

  def destroy
    authorize @comment
    @comment.destroy!

    unless policy(@jjaek).show?
      redirect_to groups_path, notice: t("comments.notices.destroyed"), status: :see_other
      return
    end

    @jjaek.reload
    prepare_comments_panel(comment: Comment.new(jjaek: @jjaek))

    respond_to do |format|
      format.turbo_stream { flash.now[:notice] = t("comments.notices.destroyed") }
      format.html { redirect_to jjaek_path(@jjaek), notice: t("comments.notices.destroyed") }
    end
  end

  private

  def set_readable_jjaek
    @jjaek = Jjaek.find(params[:jjaek_id])
    raise ActiveRecord::RecordNotFound if @jjaek.group_id.present? && !policy(@jjaek).show?

    authorize @jjaek, :show?
  end

  def set_destroy_jjaek
    @jjaek = Jjaek.find(params[:jjaek_id])
  end

  def set_comment
    @comment = @jjaek.comments.find(params[:id])
  end

  def set_comments_context
    requested_context = params[:comments_context].presence || default_comments_context

    unless COMMENTS_CONTEXTS.include?(requested_context)
      set_detail_comments_context
      return
    end

    case requested_context
    when "profile"
      set_profile_comments_context
    when "book"
      set_book_comments_context
    when "group"
      set_group_comments_context
    else
      @comments_context = requested_context.to_sym
    end
  end

  def prepare_comments_panel(comment:, editing_comment: nil)
    @comments = @jjaek.comments.includes(:user).order(created_at: :asc)
    if editing_comment.present?
      @comments = @comments.map { |record| record.id == editing_comment.id ? editing_comment : record }
    end
    @comment = comment
  end

  def default_comments_context
    action_name == "index" ? "home" : "detail"
  end

  def set_detail_comments_context
    @comments_context = :detail
    @comments_profile_user = nil
    @comments_book = nil
  end

  def set_profile_comments_context
    @comments_profile_user = User.find_by(id: params[:profile_user_id])
    return set_detail_comments_context if @comments_profile_user.blank?

    @comments_context = :profile
    @comments_book = nil
  end

  def set_book_comments_context
    @comments_book = Book.find_by(id: params[:book_id])
    return set_detail_comments_context if @comments_book.blank?
    return set_detail_comments_context unless @jjaek.book_id == @comments_book.id

    @comments_context = :book
    @comments_profile_user = nil
  end

  def set_group_comments_context
    return set_detail_comments_context if @jjaek.group_id.blank?

    @comments_context = :group
    @comments_profile_user = nil
    @comments_book = nil
  end

  def inline_comments_context?
    %i[home profile book group].include?(@comments_context)
  end

  def comment_params
    params.require(:comment).permit(:content)
  end
end
