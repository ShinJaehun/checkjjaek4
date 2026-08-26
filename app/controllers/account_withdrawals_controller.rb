class AccountWithdrawalsController < ApplicationController
  def show
  end

  def destroy
    user = current_user
    Users::WithdrawAccount.new(user, current_password: withdrawal_params[:current_password]).call!
    sign_out user

    redirect_to root_path, notice: t("account_withdrawals.notices.completed"), status: :see_other
  rescue Users::WithdrawAccount::InvalidPassword
    @error = t("account_withdrawals.errors.invalid_password")
    render :show, status: :unprocessable_content
  rescue Users::WithdrawAccount::GlobalAdmin
    @error = t("account_withdrawals.errors.global_admin")
    render :show, status: :unprocessable_content
  rescue Users::WithdrawAccount::ActiveGroupAdmin => error
    @error = t("account_withdrawals.errors.active_group_admin", groups: error.group_names.join(", "))
    render :show, status: :unprocessable_content
  rescue Users::WithdrawAccount::PendingGroupHasContent
    @error = t("account_withdrawals.errors.pending_group_content")
    render :show, status: :unprocessable_content
  rescue Users::WithdrawAccount::AlreadyWithdrawn
    sign_out current_user
    redirect_to root_path, notice: t("account_withdrawals.notices.completed"), status: :see_other
  end

  private

  def withdrawal_params
    params.fetch(:account_withdrawal, {}).permit(:current_password)
  end
end
