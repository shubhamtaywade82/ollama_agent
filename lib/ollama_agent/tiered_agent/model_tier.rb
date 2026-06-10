# frozen_string_literal: true

module OllamaAgent
  module TieredAgent
    # Named model constants for the three execution tiers.
    #
    # These are the *default* (minimal / 8 GB) model names used as fallbacks
    # when no {HardwareProfile} has been selected. All production code should
    # resolve models through {HardwareProfile.for_vram} or an explicit profile;
    # these constants exist for backwards-compatibility and testing.
    module ModelTier
      SMALL  = HardwareProfile::PROFILE_MAP[:minimal].model_small
      MEDIUM = HardwareProfile::PROFILE_MAP[:minimal].model_medium
      LARGE  = HardwareProfile::PROFILE_MAP[:minimal].model_large

      ALL = [SMALL, MEDIUM, LARGE].freeze
    end
  end
end
