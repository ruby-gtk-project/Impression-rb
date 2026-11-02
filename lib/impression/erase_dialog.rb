# frozen_string_literal: true

require "adwaita"

module Impression
  # EraseDialog is the confirmation shown before a write starts.
  #
  # Ported from upstream's src/window.rs (flash_dialog): an Adw.AlertDialog
  # naming the drive, with a destructive Erase response that starts the write.
  class EraseDialog
    HEADING = "Erase Drive?"
    BODY = "You will lose all data stored on {}"

    def initialize(device_name:, &on_erase)
      @device_name = device_name
      @on_erase = on_erase
    end

    def present(window)
      dialog.tap do |alert|
        alert.signal_connect("response") do |_alert, response|
          case response
          when "erase"
            @on_erase.call
          end
        end
      end.present(window)
    end

    def dialog
      @dialog ||= Adwaita::AlertDialog.new(HEADING, BODY.sub("{}", @device_name.to_s)).tap do |alert|
        alert.add_response("cancel", "_Cancel")
        alert.add_response("erase", "_Erase")
        alert.set_response_appearance("erase", :destructive)
        alert.default_response = "cancel"
        alert.close_response = "cancel"
      end
    end
  end
end
