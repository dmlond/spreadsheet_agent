# Author: Darin London
# The license of this source is "MIT Licence"

require 'google_drive'
require 'psych'

module SpreadsheetAgent

# SpreadsheetAgent::Db is a class that is meant to be extended by SpreadsheetAgent classes.  It
# stores shared code to instantiate and provide access to a GoogleDrive object and
# GoogleDrive::Spreadsheet object for use by the extending classes to access their Google Spreadsheets
  class Db

# This holds the GoogleDrive::Spreadsheet object that can be used to query information from the google
# spreadsheet using its API.  It cannot be changed after the object is constructed
    attr_reader :db

# This holds the GoogleDrive object instantiated with the guser and gpass in the :config. It
# cannot be changed after the object is constructed
    attr_reader :session

# This holds the hash that is constructed from the YAML :config_file. It
# cannot be changed after the object is constructed
    attr_reader :config

# Passing this attribute to the constructor will override the location of config/agent.conf.yml.
# If passed, it must be a path to a file which matches the template in config/agent.conf.yml.
# The default is to load ../config/agent.config.yaml relative to the directory containing the
# calling script $0.  This cannot be changed after the object is constructed
    attr_reader :config_file

# This is for internal use by SpreadsheetAgent classes that extend SpreadsheetAgent::Db
    def build_db
      build_config()
      unless @config['key_fields'].keys.select { |k| @config['key_fields'][k]['required'] }.count > 0
        raise SpreadsheetAgentError, "Your configuration must have at least one required key_fields key"
      end
      @session = GoogleDrive.login(@config['guser'], @config['gpass'])
      @db = @session.spreadsheet_by_title(@config['spreadsheet_name'])
    end

    private

    def build_config()
      if @config_file.nil?
        @config_file =  find_bin() + '../config/agent.conf.yml'
      end
      @config = Psych.load_file(@config_file)
    end

    def find_bin()
      File.expand_path(File.dirname( $0 )) + '/'
    end
  end
end
