# frozen_string_literal: true

# Sends test emails
class TestMailer < ActionMailer::Base
  default from: MailFromHelper.from

  def test_message(to)
    mail(
      to: to,
      subject: '[ThriveDevCenter] Email delivery test'
    ) { |format|
      format.text
      format.html
    }
  end
end
