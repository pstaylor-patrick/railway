# frozen_string_literal: true

module RailwayCli
  # Masks variable values so they do not leak onto screens or into agent transcripts.
  module Mask
    STARS = "****"
    MIN_VISIBLE_LENGTH = 8

    def self.call(value)
      s = value.to_s
      s.length < MIN_VISIBLE_LENGTH ? STARS : "#{s[0, 2]}#{STARS}"
    end
  end
end
