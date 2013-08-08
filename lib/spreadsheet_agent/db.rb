require 'google_drive'
require 'psych'

module SpreadsheetAgent

  class Db
    attr_reader :db, :session, :config_file, :config
  
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
