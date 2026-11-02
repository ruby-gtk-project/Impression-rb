# frozen_string_literal: true

require_relative "i18n"

module Impression
  # Progress is either a known fraction of the work or a pulse, for the phases
  # whose total size is not knowable in advance.
  #
  # Ported from upstream's src/flash/mod.rs (Progress), including its
  # From<(u64, u64)> conversion: a zero denominator pulses instead of dividing.
  class Progress
    attr_reader :fraction

    def self.pulse = new(nil)

    def self.of(nominator, denominator)
      case denominator.to_i
      when 0
        pulse
      else
        new(nominator.to_f / denominator)
      end
    end

    def initialize(fraction)
      @fraction = fraction
    end

    def pulse? = fraction.nil?
  end

  # FlashStatus is what the write thread publishes and the window polls once a
  # second: an active phase with its progress, or a finished run carrying the
  # error message when it failed.
  #
  # Ported from upstream's src/flash/mod.rs (FlashPhase, FlashStatus), with the
  # per-phase page copy from src/window.rs (update_flashing_page) keyed by the
  # same phase names.
  class FlashStatus
    # N_ marks these for extraction without looking them up: the table is built
    # at load time, before a locale is set, and StatusView translates each
    # string where it shows it.
    extend Gettext

    PHASES = {
      download:      {
        title:       N_("Downloading Image"),
        description: N_("Writing will begin once the download is completed"),
        icon_name:   "folder-download-symbolic",
      },
      extract:       {
        title:       N_("Extracting Image"),
        description: N_("Reading the source image"),
        icon_name:   "media-optical-cd-symbolic",
      },
      process_image: {
        title:       N_("Processing Image"),
        description: N_("Splitting the install image"),
        icon_name:   "media-optical-cd-symbolic",
      },
      partition:     {
        title:       N_("Partitioning Drive"),
        description: N_("Do not remove the drive"),
        icon_name:   "usb-stick-symbolic",
      },
      build_image:   {
        title:       N_("Preparing Installer Image"),
        description: N_("Building the installer filesystem"),
        icon_name:   "flash-symbolic",
      },
      copy:          {
        title:       N_("Writing"),
        description: N_("This could take a while"),
        icon_name:   "flash-symbolic",
      },
    }.freeze

    attr_reader :phase, :progress, :error

    def self.active(phase, progress) = new(:active, phase: phase, progress: progress)

    def self.done(error = nil) = new(:done, error: error)

    def initialize(state, phase: nil, progress: nil, error: nil)
      @state = state
      @phase = phase
      @progress = progress
      @error = error
    end

    def active? = @state == :active

    def done? = @state == :done

    def failed? = done? && !error.nil?

    # The flashing page's copy for this status' phase.
    def page = PHASES.fetch(phase, PHASES[:copy])
  end
end
