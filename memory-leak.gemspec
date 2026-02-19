# frozen_string_literal: true

require_relative "lib/memory/leak/version"

Gem::Specification.new do |spec|
	spec.name = "memory-leak"
	spec.version = Memory::Leak::VERSION
	
	spec.summary = "A memory leak monitor."
	spec.authors = ["Samuel Williams"]
	spec.license = "MIT"
	
	spec.cert_chain  = ["release.cert"]
	spec.signing_key = File.expand_path("~/.gem/release.pem")
	
	spec.homepage = "https://github.com/socketry/memory-leak"
	
	spec.metadata = {
		"documentation_uri" => "https://socketry.github.io/memory-leak/",
		"source_code_uri" => "https://github.com/socketry/memory-leak.git",
	}
	
	spec.files = Dir["{lib}/**/*", "*.md", base: __dir__]
	
	spec.add_dependency "process-metrics", "~> 0.10"
	
	spec.required_ruby_version = ">= 3.2"
end
