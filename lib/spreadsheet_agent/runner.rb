# Author: Darin London
# The license of this source is "New BSD Licence"
require 'spreadsheet_agent/db'

module SpreadsheetAgent

  class Runner < SpreadsheetAgent::Db

    attr_accessor :dry_run, :run_in_serial, :debug, :sleep_between, :agent_bin
    attr_reader :query_fields, :only_pages
    @skip_entry_code = nil
    @skip_goal_code = nil

    def initialize(attributes = { })
      if (!attributes[:skip_pages].nil? && !attributes[:only_pages].nil?)
        raise SpreadsheetAgentError, "You cannot construct a runner with both only_pages and skip_pages"
      end

      @dry_run = attributes[:dry_run]
      @run_in_serial = attributes[:run_in_serial]
      @debug = attributes[:debug]
      @config_file = attributes[:config_file]

      @sleep_between = 5
      unless attributes[:sleep_between].nil?
        @sleep_between = attributes[:sleep_between]
      end
    
      @agent_bin = find_bin() + '../agent_bin'
      unless attributes[:agent_bin].nil?
        @agent_bin = attributes[:agent_bin]      
      end

      if attributes[:skip_pages]
        @skip_pages = attributes[:skip_pages].clone
      end

      if attributes[:only_pages]
        @only_pages = attributes[:only_pages].clone
      end

      build_db()
      @query_fields = build_query_fields()
    
      if @skip_pages
        skip_pages_if do |page|
          @skip_pages.include? page
        end
      end
    
      if @dry_run
        @debug = true
      end
    end
  
    def skip_pages_if(&skip_code)
      @only_pages = @db.worksheets.collect{ |p| p.title }.reject{ |ptitle| skip_code.call(ptitle) }
      self
    end

    def only_pages_if(&include_code)
      @only_pages = @db.worksheets.collect{ |p| p.title }.select { |ptitle| include_code.call(ptitle) }
      self
    end

    def skip_entry(&skip_code)
      @skip_entry_code = skip_code
      self
    end

    def skip_goal(&skip_code)
      @skip_goal_code = skip_code
      self
    end

    def process!(&runner_code)
      get_runnable_entries().each do |entry_info|
        entry_page, runnable_entry = entry_info
        if runner_code.nil?
          default_process(runnable_entry)
        elsif @dry_run
          $stderr.print "Would run #{ entry_page.title } #{ runnable_entry.inspect }"
        else
          runner_code.call(runnable_entry, entry_page)
        end
        sleep @sleep_between
      end
    end

    private

    def get_runnable_entries
      runnable_entries = []
      get_pages_to_process().each do |page|
        $stderr.puts "Processing page " + page.title if @debug
        runnable_entries += page.list.reject { |check_entry |  @skip_entry_code.nil? ? false : @skip_entry_code.call(check_entry)  }.collect{ |entry| [page, entry] }
      end

      return runnable_entries
    end

    def run_entry_goal(entry, goal)
      $stderr.puts "Running goal #{goal}" if @debug

      goal_agent = [@agent_bin, "#{ goal }_agent.rb"].join('/')
      cmd = [goal_agent]

      @query_fields.each do |query_field|
        if entry[query_field]
          cmd.push entry[query_field]
        end
      end

      command = cmd.join(' ')
      command += '&' unless @run_in_serial
      $stderr.puts command if @debug
      if File.executable?(goal_agent)
        unless @dry_run
          system(command)
        end
      else
        $stderr.puts "AGENT RUNNER DOES NOT EXIST!" if @debug
      end
    end

    def default_process(runnable_entry)
      title = query_fields.collect { |field| runnable_entry[field] }.join(' ')
      $stderr.puts "Checking goals for #{ title }" if @debug

      runnable_entry.keys.reject { |key|
        if @skip_goal_code.nil?
          false
        else
          ( @skip_goal_code.call(key) )
        end
      }.each do |goal|
        run_entry_goal(runnable_entry, goal)
        sleep @sleep_between
      end
    end
  
    def build_query_fields
      @config['key_fields'].keys.sort { |a,b| @config['key_fields'][a]['rank'] <=> @config['key_fields'][b]['rank'] }
    end

    def get_pages_to_process
      if @only_pages.nil?
        @db.worksheets
      else
        @db.worksheets.select { |page|  @only_pages.include? page.title }
      end
    end
  end #Runner
end #SpreadsheetAgent

