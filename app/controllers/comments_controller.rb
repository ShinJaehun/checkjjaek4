class CommentsController < ApplicationController
  COMMENTS_CONTEXTS = %w[detail home].freeze

  before_action :set_jjaek
  before_action :set_comments_context, only: %i[create destroy]
  before_action :set_comment, only: %i[update destroy]

  def index
    @comments_context = :home
    @comments_panel_closed = params[:comments_context] == "home" && params[:panel_state] == "closed"
    prepare_comments_panel(comment: Comment.new(jjaek: @jjaek))

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to jjaek_path(@jjaek, anchor: helpers.comments_panel_dom_id(@jjaek)) }
    end
  end

  def create
    @comment = Comment.new(comment_params.merge(jjaek: @jjaek, user: current_user))
    authorize @comment

    if @comment.save
      Notification.notify_comment_created(@comment)
      @jjaek.reload
      prepare_comments_panel(comment: Comment.new(jjaek: @jjaek))

      respond_to do |format|
        format.turbo_stream
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

    if @comment.update(comment_params)
      redirect_to jjaek_path(@jjaek), notice: t("comments.notices.updated")
    else
      @comments = @jjaek.comments.includes(:user).order(created_at: :asc)
      prepare_visible_requote_counts_for([ @jjaek ])
      render "jjaeks/show", status: :unprocessable_content
    end
  end

  def destroy
    authorize @comment
    @comment.destroy!

    @jjaek.reload
    prepare_comments_panel(comment: Comment.new(jjaek: @jjaek))

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to jjaek_path(@jjaek), notice: t("comments.notices.destroyed") }
    end
  end

  private

  def set_jjaek
    @jjaek = Jjaek.find(params[:jjaek_id])
    authorize @jjaek, :show?
  end

  def set_comment
    @comment = @jjaek.comments.find(params[:id])
  end

  def set_comments_context
    @comments_context =
      if COMMENTS_CONTEXTS.include?(params[:comments_context])
        params[:comments_context].to_sym
      else
        :detail
      end
  end

  def prepare_comments_panel(comment:)
    @comments = @jjaek.comments.includes(:user).order(created_at: :asc)
    @comment = comment
  end

  def comment_params
    params.require(:comment).permit(:content)
  end
end
