Gem::Specification.new do |s|
  s.name        = 'spreadsheet_agent'
  s.version     = '0.0.1'
  s.date        = '2013-08-12'
  s.summary     = "SpreadsheetAgent is a framework for creating distributed pipelines across many different servers, each using the same google spreadsheet as a control panel."
  s.description = <<-EOF
SpreadsheetAgent is a framework for creating distributed pipelines across many different servers. It is extensible, and flexible.  It does not specify what goals any pipeline should
be working towards, or which goals are prerequisites for other goals, but it does
provide logic for easily defining these relationships based on your own needs.
It does this by providing a subsumption architecture, whereby many small, highly
focused agents are written to perform specific goals, and also know what prerequisites
and resources they require to perform them.  In addition, it is designed from the beginning
to support the creation of simple human-computational workflows.
EOF
  s.author     = "Darin London"
  s.license    = "MIT"
  s.email       = 'darin.london@duke.edu'
  s.files       = Dir["lib/**/*"] + Dir["test/**/*"]
  s.test_files = Dir["test/*.rb"]
  s.homepage    =
    'http://rubygems.org/gems/spreadsheet_agent'
  s.add_runtime_dependency "google_drive", "~> 0.3"
  s.add_runtime_dependency "capture_io", "~> 0.1"
  s.add_development_dependency "rake", "~> 0.9.2"
  s.add_development_dependency "shoulda-context", "~> 1.1"
end
