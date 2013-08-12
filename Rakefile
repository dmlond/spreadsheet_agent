require 'rake'
require 'rake/testtask'

desc "Run all unit tests"
task :default => [:db, :agent, :runner]

desc "Test SpreadsheetAgent::DB"
Rake::TestTask.new do |t|
  t.name = :db
  t.test_files = ['test/spreadsheet_agent_db_test.rb']
end

desc "Test SpreadsheetAgent::Agent"
Rake::TestTask.new do |t|
  t.name = :agent
  t.test_files = ['test/spreadsheet_agent_test.rb']
end

task :agent => [:db]

desc "Test SpreadsheetAgent::Runner"
Rake::TestTask.new do |t|
  t.name = :runner
  t.test_files = ['test/spreadsheet_agent_runner_test.rb']
end

task :runner => [:db]
