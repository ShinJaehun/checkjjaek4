module Users
  class RegistrationsController < Devise::RegistrationsController
    def destroy
      redirect_to account_withdrawal_path, alert: t("account_withdrawals.errors.use_confirmation"), status: :see_other
    end
  end
end
