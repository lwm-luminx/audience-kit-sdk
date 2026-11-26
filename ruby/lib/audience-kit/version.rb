# frozen_string_literal: true

module Audience
  module Kit
    # The gem's semantic version. It is versioned on its own, apart from the Swift and Kotlin SDKs' VERSION.
    VERSION = "0.3.0"

    # The API contract this SDK speaks, the date it was last broken: sent as +X-AudienceKit-API-Version+ on every
    # request and kept on each {Credential}.
    API_VERSION = "2026-10-11"
  end
end
