# frozen_string_literal: true

require_relative "lib/audience-kit/version"

Gem::Specification.new do |spec|
  spec.name = "audience-kit"
  spec.version = Audience::Kit::VERSION
  spec.authors = ["Love Wins Media, Inc."]

  spec.summary = "AudienceKit SDK for Ruby: sign people in and read an audience's venues, events, news and chat"
  spec.description = <<~TEXT
    Ruby client for AudienceKit, the platform behind Hot Mess. Source-available under the AudienceKit SDK License 1.2:
    use it only with AudienceKit as hosted by Love Wins Media, Inc. See LICENSE.
  TEXT
  spec.homepage = "https://audiencekit.com"
  # Source-available, not open source (LICENSE): no SPDX identifier exists for it, so RubyGems shows this reference.
  spec.license = "LicenseRef-AudienceKit-SDK-1.2"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/lwm-luminx/audience-kit-sdk/tree/main/ruby"
  spec.metadata["documentation_uri"] = "https://developer.audiencekit.com/sdks/ruby/"
  spec.metadata["bug_tracker_uri"] = "https://github.com/lwm-luminx/audience-kit-sdk/issues"
  spec.metadata["changelog_uri"] = "https://github.com/lwm-luminx/audience-kit-sdk/blob/main/ruby/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Only what a program that requires the gem needs, plus the license, README, changelog and guides (which the YARD
  # reference on RubyDoc.info includes).
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*.rb", "sig/**/*.rbs", "docs/*.md", ".yardopts"] + %w[LICENSE README.md CHANGELOG.md]
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.9"
end
