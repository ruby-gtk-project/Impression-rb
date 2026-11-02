# frozen_string_literal: true

require "adwaita"

module Impression
  # StatusView is the stack the window shows instead of the chooser: the
  # waiting spinner, the no-drives page, the progress page, and the success and
  # failure pages a finished write lands on.
  #
  # Ported from upstream's data/resources/blueprints/window.blp (the Gtk.Stack
  # named stack, with its loading / no_devices / success / failure / flashing
  # pages) together with the handlers src/window.rs attaches to their buttons.
  class StatusView
    APP_ICON = "io.gitlab.adhami3310.Impression"

    LOADING = "loading"
    NO_DEVICES = "no_devices"
    SUCCESS = "success"
    FAILURE = "failure"
    FLASHING = "flashing"

    # The pages a run owns: a device change must not navigate away from them.
    OWNED_BY_RUN = [FLASHING, FAILURE, SUCCESS].freeze

    def initialize(on_done:, on_retry:, on_cancel:)
      @on_done = on_done
      @on_retry = on_retry
      @on_cancel = on_cancel
    end

    def build
      stack.tap do |pages|
        pages.add_named(loading_spinner, LOADING)
        pages.add_named(no_devices_page, NO_DEVICES)
        pages.add_named(success_page, SUCCESS)
        pages.add_named(failure_page, FAILURE)
        pages.add_named(flashing_page, FLASHING)

        success_page.tap do |page|
          page.child = success_box

          success_box.tap do |box|
            box.append(done_button)

            done_button.signal_connect("clicked") { @on_done.call }
          end
        end

        failure_page.tap do |page|
          page.child = failure_clamp

          failure_clamp.tap do |clamp|
            clamp.child = failure_box

            failure_box.tap do |box|
              box.append(error_scroller)
              box.append(try_again_button)

              error_scroller.child = error_message_label
              try_again_button.signal_connect("clicked") { @on_retry.call }
            end
          end
        end

        flashing_page.tap do |page|
          page.child = flashing_box

          flashing_box.tap do |box|
            box.append(progress_bar)
            box.append(cancel_button)

            cancel_button.signal_connect("clicked") { @on_cancel.call }
          end
        end
      end
    end

    def show(name) = stack.visible_child_name = name

    def visible = stack.visible_child_name

    # True while a run owns the view, which is when a device change must leave
    # the visible page alone.
    def owned_by_run? = OWNED_BY_RUN.include?(visible)

    # Upstream's update_flashing_page: the copy for the phase the write is in.
    def phase=(page)
      flashing_page.title = page[:title]
      flashing_page.description = page[:description]
      flashing_page.icon_name = page[:icon_name]
    end

    # A fraction shows the default percentage text; a pulse has no meaningful
    # percentage, so the text is blanked.
    def progress=(progress)
      case progress.pulse?
      when true
        progress_bar.text = ""
        progress_bar.pulse
      else
        progress_bar.text = nil
        progress_bar.fraction = progress.fraction
      end
    end

    def error=(message)
      error_message_label.label = message.to_s
      error_message_label.visible = !message.to_s.empty?
    end

    def reset_progress
      progress_bar.text = nil
      progress_bar.fraction = 0.0
    end

    def stack
      @stack ||= Gtk::Stack.new.tap do |pages|
        pages.transition_type = :crossfade
      end
    end

    def loading_spinner
      @loading_spinner ||= Gtk::Spinner.new.tap do |spinner|
        spinner.valign = :center
        spinner.halign = :center
        spinner.height_request = 28
        spinner.width_request = 28
        spinner.spinning = true
      end
    end

    def no_devices_page
      @no_devices_page ||= Adwaita::StatusPage.new.tap do |page|
        page.icon_name = APP_ICON
        page.title = "No Drives"
        page.description = "Insert a drive to write to"
      end
    end

    def success_page
      @success_page ||= Adwaita::StatusPage.new.tap do |page|
        page.icon_name = "check-round-outline-symbolic"
        page.title = "Writing Completed"
        page.description = "The drive can be safely removed"
      end
    end

    def success_box
      @success_box ||= Gtk::Box.new(:vertical, 12)
    end

    def done_button
      @done_button ||= Gtk::Button.new.tap do |button|
        button.label = "Finish"
        button.use_underline = true
        button.valign = :center
        button.halign = :center
        button.add_css_class("suggested-action")
        button.add_css_class("pill")
      end
    end

    def failure_page
      @failure_page ||= Adwaita::StatusPage.new.tap do |page|
        page.icon_name = "error-symbolic"
        page.title = "Writing Unsuccessful"
      end
    end

    def failure_clamp
      @failure_clamp ||= Adwaita::Clamp.new.tap do |clamp|
        clamp.maximum_size = 600
        clamp.tightening_threshold = 400
      end
    end

    def failure_box
      @failure_box ||= Gtk::Box.new(:vertical, 12)
    end

    def error_scroller
      @error_scroller ||= Gtk::ScrolledWindow.new.tap do |scroller|
        scroller.min_content_height = 100
        scroller.max_content_height = 200
        scroller.add_css_class("card")
      end
    end

    def error_message_label
      @error_message_label ||= Gtk::Label.new.tap do |label|
        label.wrap = true
        label.wrap_mode = :word_char
        label.xalign = 0
        label.yalign = 0
        label.add_css_class("monospace")
        label.add_css_class("error-message")
      end
    end

    def try_again_button
      @try_again_button ||= Gtk::Button.new.tap do |button|
        button.label = "Retry"
        button.use_underline = true
        button.valign = :center
        button.halign = :center
        button.add_css_class("suggested-action")
        button.add_css_class("pill")
      end
    end

    def flashing_page
      @flashing_page ||= Adwaita::StatusPage.new.tap do |page|
        page.icon_name = "flash-symbolic"
        page.title = "Writing"
        page.description = "Do not remove the drive"
      end
    end

    def flashing_box
      @flashing_box ||= Gtk::Box.new(:vertical, 36)
    end

    def progress_bar
      @progress_bar ||= Gtk::ProgressBar.new.tap do |bar|
        bar.valign = :center
        bar.halign = :center
        bar.show_text = true
      end
    end

    def cancel_button
      @cancel_button ||= Gtk::Button.new.tap do |button|
        button.label = "_Cancel"
        button.use_underline = true
        button.valign = :center
        button.halign = :center
        button.add_css_class("pill")
      end
    end
  end
end
