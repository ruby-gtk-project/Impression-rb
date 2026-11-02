# frozen_string_literal: true

require "adwaita"

module Impression
  # DragOverlay wraps a widget and fades a "drop here" status page over it
  # while a drag is hovering.
  #
  # Ported from upstream's src/widgets/drag_overlay.rs, which is an Adw.Bin
  # subclass holding an overlay, a crossfading revealer and a status page, with
  # the revealer following the drop target's current-drop.
  #
  # Upstream registers it as a GObject type so the blueprint can instantiate
  # it; this port composes the same three widgets and hands the Bin back from
  # build, which is all the window needs of it.
  class DragOverlay
    ICON_NAME = "document-send-symbolic"
    CSS_CLASS = "drag-overlay-status-page"

    def initialize(title:, child:)
      @title = title
      @child = child
    end

    def build
      bin.tap do |root|
        root.child = overlay

        overlay.tap do |stack|
          stack.child = @child
          stack.add_overlay(revealer)

          revealer.tap do |reveal|
            reveal.child = status_page
          end
        end
      end
    end

    # Upstream's set_drop_target: the controller goes on the widget, and the
    # revealer shows exactly while a drop is in flight over it.
    def drop_target=(target)
      target.signal_connect("notify::current-drop") do |drop_target, _parameter|
        revealer.reveal_child = !drop_target.current_drop.nil?
      end
      bin.add_controller(target)
    end

    def bin = @bin ||= Adwaita::Bin.new

    def overlay = @overlay ||= Gtk::Overlay.new

    def revealer
      @revealer ||= Gtk::Revealer.new.tap do |reveal|
        reveal.can_target = false
        reveal.transition_type = :crossfade
        reveal.reveal_child = false
      end
    end

    def status_page
      @status_page ||= Adwaita::StatusPage.new.tap do |page|
        page.title = @title
        page.icon_name = ICON_NAME
        page.add_css_class(CSS_CLASS)
      end
    end
  end
end
