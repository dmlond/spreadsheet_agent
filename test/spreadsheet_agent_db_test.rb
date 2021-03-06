require 'test/unit'
require 'spreadsheet_agent/db'

class TC_SpreadsheetAgentDbTest < Test::Unit::TestCase
  def test_instantiate_db
    conf_file = File.expand_path(File.dirname( __FILE__ )) + '/../config/agent.conf.yml'
    unless File.exists?( conf_file )
      $stderr.puts "You must create a valid test Google Spreadsheet and a valid #{ conf_file } configuration file pointing to it to run the tests. See README.txt file for more information on how to run the tests."
      exit
    end

    google_db = SpreadsheetAgent::Db.new()
    assert_not_nil google_db
    assert_instance_of(SpreadsheetAgent::Db, google_db)
  end
end #TC_SpreadsheetAgentDbTest
