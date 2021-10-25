lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "cocoapods/dev/env/version"

Gem::Specification.new do |spec|
  spec.name          = "cocoapods-dev-env"
  spec.version       = Cocoapods::Dev::Env::VERSION
  spec.authors       = ["吴锡苗"]
  spec.email         = ["wuximiao@rd.netease.com"]

  spec.summary       = %q{a cocoapod plugin for dev in mutipods}
  spec.description   = %q{make it easy to dev in mutipods}
  spec.homepage      = "https://github.com/YoudaoMobile/cocoapods-dev-env"
  spec.license       = "MIT"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/YoudaoMobile/cocoapods-dev-env.git"
  #spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'luna-binary-uploader'
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 10.0"
end
