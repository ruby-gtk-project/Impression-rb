# frozen_string_literal: true

require "gtk4"

require_relative "i18n"

module Impression
  # Notifier posts the end-of-write notification.
  #
  # Ported from upstream's src/window.rs (send_notification and the free
  # function it spawns): a notification is only worth sending when the window
  # is not the window the user is looking at. Upstream goes through the XDG
  # notification portal with ashpd; Gio's own send_notification takes the same
  # route for a sandboxed app and talks to the session's notification service
  # otherwise.
  class Notifier
    include Gettext

    TITLE = "Impression"
    ID = "impression-write"

    def initialize(application:, window:)
      @application = application
      @window = window
    end

    def notify(message)
      case @window.active?
      when true
        nil
      else
        @application.send_notification(ID, notification(message))
      end
    end

    private

      def notification(message)
        Gio::Notification.new(_(TITLE)).tap do |gio_notification|
          gio_notification.body = message
          gio_notification.priority = :normal
        end
      end
  end
end
