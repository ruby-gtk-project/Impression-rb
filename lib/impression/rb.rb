# frozen_string_literal: true

require_relative "rb/version"

module Impression
  # Rb is the kettle-jem-generated gem namespace (impression-rb -> Impression::Rb)
  # that spec/spec_helper.rb requires to prove the gem loads under its
  # packaged name, separately from Impression::Application and friends, which
  # exe/impression reaches through the plain "impression" require instead.
  module Rb
  end
end
