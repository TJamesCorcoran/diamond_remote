$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "diamond_remote/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "diamond_remote"
  s.version     = DiamondRemote::VERSION
  s.authors     = ["T James Corcoran"]
  s.email       = ["tjamescorcoran@gmail.com"]
  s.homepage    = "https://github.com/tjamescorcoran"
  s.summary     = "Tools for comic book merchants to interact with Diamond Comics"
  s.description = ""
  s.license     = ""

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "mechanize",  "2.3"
end
