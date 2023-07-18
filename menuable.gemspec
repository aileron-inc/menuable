# frozen_string_literal: true

require_relative "lib/menuable/version"

Gem::Specification.new do |spec|
  spec.name = "menuable"
  spec.version = Menuable::VERSION
  spec.authors = ["Masa (Aileron inc)"]
  spec.email = ["masa@aileron.cc"]

  spec.summary = "Allow yaml definition of sidemenu in rails"
  spec.description = <<~TEXT
    This library provides menu.yml and controller macros to manage routes and sidebar implementations when implementing management functions in rails.
  TEXT
  spec.homepage = "https://github.com/aileron-inc/menuable"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/aileron-inc/menuable"
  spec.metadata["changelog_uri"] = "https://github.com/aileron-inc/menuable"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  spec.add_dependency "activesupport"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.metadata["rubygems_mfa_required"] = "true"
end
