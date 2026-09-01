module Admin
  class JjaeksController < ApplicationController
    def hide
      jjaek = Jjaek.find(params[:id])
      authorize jjaek, :hide?
      Jjaeks::Hide.new(jjaek, actor: current_user, **moderation_action_params).call!

      redirect_to jjaek_path(jjaek), notice: t("admin.jjaeks.notices.hidden")
    rescue Jjaeks::Hide::Error, ActiveRecord::RecordInvalid
      redirect_to jjaek_path(jjaek), alert: t("admin.jjaeks.alerts.hide_failed")
    end

    def restore
      jjaek = Jjaek.find(params[:id])
      authorize jjaek, :restore?
      Jjaeks::Restore.new(jjaek, actor: current_user, **moderation_action_params).call!

      redirect_to jjaek_path(jjaek), notice: t("admin.jjaeks.notices.restored")
    rescue Jjaeks::Restore::Error, ActiveRecord::RecordInvalid
      redirect_to jjaek_path(jjaek), alert: t("admin.jjaeks.alerts.restore_failed")
    end

    private

    def moderation_action_params
      params.require(:moderation_action).permit(:public_reason, :internal_note).to_h.symbolize_keys
    end
  end
end
