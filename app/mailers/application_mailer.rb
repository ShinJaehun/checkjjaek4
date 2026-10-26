class ApplicationMailer < ActionMailer::Base
  default from: "책짹 <account@jjaek.kr>", reply_to: "support@jjaek.kr"
  layout "mailer"
end
