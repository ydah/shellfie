# frozen_string_literal: true

require_relative "lib/shellfie/version"

Gem::Specification.new do |spec|
  spec.name = "shellfie"
  spec.version = Shellfie::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "Terminal screenshot-style image generator"
  spec.description = "Compile YAML terminal scenes or recorded sessions into accessible HTML, semantic transcripts, SVG, raster images, and animations."
  spec.homepage = "https://github.com/ydah/shellfie"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir.glob("{exe,lib,assets,schema}/**/*", File::FNM_DOTMATCH).select { |f| File.file?(f) }.concat(%w[README.md CHANGELOG.md LICENSE]).reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = %w[shellfie shf]
  spec.require_paths = ["lib"]

  spec.add_dependency "mini_magick", ">= 4.12", "< 6"
end
