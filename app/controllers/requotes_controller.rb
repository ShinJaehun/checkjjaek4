class RequotesController < ApplicationController
  def index
    @jjaek = Jjaek.find(params[:jjaek_id])
    authorize @jjaek, :requote?

    @requotes = policy_scope(Jjaek)
      .where(quoted_jjaek_id: @jjaek.id)
      .includes(:user, :book, :target_user, :likes, :comments, quoted_jjaek: [ :user, :book ])
      .recent
  end
end
