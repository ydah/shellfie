# frozen_string_literal: true

require_relative "lib/shellfie/version"

Gem::Specification.new do |spec|
  spec.name = "shellfie"
  spec.version = Shellfie::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "Terminal screenshot-style image generator"
  spec.description = "Generate beautiful terminal screenshot-style PNG images and animated GIFs from YAML configuration files. Perfect for README files and documentation."
  spec.homepage = "https://github.com/ydah/shellfie"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = %w[shellfie shf]
  spec.require_paths = ["lib"]

  spec.add_dependency "mini_magick", ">= 4.12"
end
