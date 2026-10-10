module Users
  class RegistrationsController < Devise::RegistrationsController
    rate_limit to: 60, within: 1.hour, by: -> { request.remote_ip },
               with: :authentication_rate_limit_exceeded, only: :create

    def destroy
      redirect_to account_withdrawal_path, alert: t("account_withdrawals.errors.use_confirmation"), status: :see_other
    end
  end
end
