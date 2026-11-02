# frozen_string_literal: true

require "adwaita"

require_relative "i18n"

module Impression
  # StopWritingDialog asks whether to abandon a write in progress.
  #
  # Ported from upstream's src/window.rs (cancel_request): the cancel button and
  # the window's close request both raise it, and only the destructive Stop
  # Writing response clears the running flag.
  class StopWritingDialog
    include Gettext

    HEADING = "Stop Writing?"
    BODY = "This might leave the drive in a faulty state"

    def initialize(&on_stop)
      @on_stop = on_stop
    end

    def present(window)
      dialog.tap do |alert|
        alert.signal_connect("response") do |_alert, response|
          case response
          when "stop"
            @on_stop.call
          end
        end
      end.present(window)
    end

    def dialog
      @dialog ||= Adwaita::AlertDialog.new(_(HEADING), _(BODY)).tap do |alert|
        alert.add_response("cancel", _("_Cancel"))
        alert.add_response("stop", _("_Stop Writing"))
        alert.set_response_appearance("stop", :destructive)
        alert.default_response = "cancel"
        alert.close_response = "cancel"
      end
    end
  end
end
