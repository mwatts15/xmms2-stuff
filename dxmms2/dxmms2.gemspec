# coding: utf-8

Gem::Specification.new do |spec|
  spec.name          = "dxmms2"
  spec.version       = "1.1.0"
  spec.authors       = ["Mark Watts"]
  spec.email         = ["wattsmark2015@gmail.com"]
  spec.summary       = %q{A client for working with xmms2}
  spec.description   = File.new("./README.md").read()
  spec.homepage      = "http://github.com/mwatts15/xmms2-stuff"
  spec.license       = "MPL-2.0"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["."]

  spec.add_development_dependency "bundler", ">= 2.2.10"
  spec.add_development_dependency "rake", ">= 12.3.2"
  spec.add_runtime_dependency "glib2", "~> 3.4.3"
  spec.add_runtime_dependency "xmms2_utils", "~> 0.1.2"
  spec.add_runtime_dependency "markw-dmenu", "~> 1.2.0"
end
