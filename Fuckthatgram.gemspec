# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'Fuckthatgram/version'

Gem::Specification.new do |spec|
  spec.name          = "Fuckthatgram"
  spec.version       = Fuckthatgram::VERSION
  spec.authors       = ["Roman"]
  spec.email         = ["roman@pramberger.ch"]

  spec.summary       = "Ruby fork of the unofficial PHP Instagram API #mgp25/Instagram-API"
  spec.description   = "Ruby fork of the unofficial PHP Instagram API https://github.com/mgp25/Instagram-API"
  spec.homepage      = "TODO: Put your gem's website or public repo URL here."
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "json", '~> 0'
  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency 'fastimage', '~> 0'
end
