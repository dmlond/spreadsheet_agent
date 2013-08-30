# Author: Darin London
# The license of this source is "New BSD Licence"
require 'spreadsheet_agent/db'

module SpreadsheetAgent


# SpreadsheetAgent::Runner is a class designed to facilitate the automated traversal of all, or some
# defined set of pages, entries, and goals defined in a SpreadsheetAgent compatible Google Spreadsheet,
# and run agents or processes on them.  By placing a SpreadsheetAgent::Runner script into the scheduling
# system (cron, etc.) on one or more compute nodes, desired pages, entries, and goals can be processed
# efficiently over a period of time, and new pages, entries, or goals can be automatically picked up
# as they are introduced.  Runners can be designed to automate the submission of agent scripts, check
# the status of jobs, aggregate information about job status, or automate cleanup tasks.
  class Runner < SpreadsheetAgent::Db

# Boolean. Optional (default false). If true, run will generate the commands that
# it would run for all runnable entry-goals, print them to STDERR, but not actually
# run the commands. Automatically sets debug to 1.
# Note, if the process_entries_with coderef is overridden, dry_run is ignored.
    attr_accessor :dry_run

# Boolean, Optional (default false). If true, the default process_entries_with PROC
# runs each agent_script executable in the foreground, rather than in the background,
# thus in serial. If false, all agent_script executables are run in parallel, in the
# background.  This is not used when process_entries_with is set to a different PROC.
    attr_accessor :run_in_serial

# Boolean, Optional (default false). If true, information about pages, entries, and
# goals that are checked and filtered is printed to STDERR.
    attr_accessor :debug

# Integer, Optional (default 5). The number of seconds that the runner sleeps between
# each call to process an entry-goal.
    attr_accessor :sleep_between

# String Path, Optional.  The path to the directory containing agent executable programs that
# the default process PROC executes.  The default is the ../agent_bin directory relative
# to the directory containing the calling script, $0.
    attr_accessor :agent_bin

# Readonly access to the Hash of field - value key_fields, as defined in :config
    attr_reader :query_fields

# Readonly access to the array of pages to be processed.  Only pages will only be defined
# when :only_pages or :skip_pages are defined in the constructor params, or when the skip_pages_if,
# or only_pages_if methods are called.
    attr_reader :only_pages
    
    @skip_entry_code = nil
    @skip_goal_code = nil

# Create a new SpreadsheetAgent::Runner.  Can be created with any of the following optional attributes:
# * :skip_pages - raises SpreadsheetAgentError if passed along with :only_pages
# * :only_pages - raises SpreadsheetAgentError if passed along with :skip_pages
# * :dry_run
# * :run_in_serial
# * :debug
# * :config_file (see SpreadsheetAgent::Db)
# * :sleep_between
# * :agent_bin
#
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

# Provide a PROC designed to intelligently filter out pages that are not to be processed.
# If not called, all pages not defined in :only_pages, or :skip_pages parameters in the constructor,
# or a previous call to only_pages_if will be processed.
# This will override only_pages, or skip_pages passed as arguments to the constructor, and
# any previous call to skip_pages_if, or only_pages_if.  The PROC should take the title of
# a page as a string, and return true if a process decides to skip the page, false otherwise.
# Must be called before the process! method to affect the pages it processes.  Returns the runner
# self to facilitate chained processing with skip_goal, skip_entry, and/or process! if desired.
#
#   skip pages whose title contains 'skip'
#   runner.skip_pages_if {|title| title.match(/skip/) }.process!
#
#   Same, but without calling process so that skip_entry or skip_goal can be called on the runner
#   runner.skip_pages_if do |title|
#     title.match(/skip/)
#   end
#   ... can call skip_entry, skip_goal, etc
#   runner.process!
#
    def skip_pages_if(&skip_code)
      @only_pages = @db.worksheets.collect{ |p| p.title }.reject{ |ptitle| skip_code.call(ptitle) }
      self
    end

# Provide a PROC desinged to intelligently determine pages to process. If not called, all pages
# not affected by the :skip_pages, or :only_pages constructor params, or a previous call to
# skip_pages_if will be processed.
# This will override only_pages, or skip_pages passed as arguments to the constructor, and
# any previous call to skip_pages_if, or only_pages_if.  The PROC should take the title of
# a page as a string, and return true if a process decides to include the page, false otherwise.
# Must be called before the process! method to affect the pages it processes.  Returns the runner
# self to facilitate chained processing with skip_goal, skip_entry, and/or process! if desired.
#
#   include only pages whose title begins with 'foo'
#   runner.only_pages_if {|title| title.match(/^foo/)}.process!
#
#   Same, but without calling process so that skip_entry or skip_goal can be called on the runner
#   runner.only_pages_if do |title|
#     title.match(/^foo/)
#   end
#   ... can call skip_entry, skip_goal
#   runner.process!
#
    def only_pages_if(&include_code)
      @only_pages = @db.worksheets.collect{ |p| p.title }.select { |ptitle| include_code.call(ptitle) }
      self
    end

# Provide a PROC desinged to intelligently determine entries on any page to skip. If not called,
# all entries on processed pages will be processed.
# The PROC should take a GoogleDrive::List representing the record in the spreadsheet, which can be accessed
# as a Hash with fields as key and that fields value as value.  It should return true if the code decides to
# skip processing the entry, false otherwise.  Must be called before the process! method to affect the entries
# on each page that it processes.  Returns the runner self to facilitate chained processing with skip_pages_if,
# only_pages_if, skip_goal, and/or process! if desired.
#
#   skip entries which have run foo or bar
#   runner.only_pages_if {|entry| entry['foo'] == 1 || entry['bar'] == 1 }.process!
#
#   skip entries that a human reading the spreadsheet has annotated with less than 3.5 in the 'threshold' field
#   runner.only_pages_if do |entry|
#     entry['threshold'] < 3.5
#   end
#   ... can call skip_pages_if, only_pages_if, skip_goal
#   runner.process!
#
    def skip_entry(&skip_code)
      @skip_entry_code = skip_code
      self
    end

# Provide a PROC desinged to skip a specific goal in any entry on all pages processed. If not called,
# all goals of each entry and page to be processed by the runner will be processed.
#   [note!] Ignored when a PROC is passed to the process! method, e.g. it is only used when process! executes
#   agent scripts for the goal.
# The PROC should take a string, which will be one of the header fields in the spreadsheet.  It should return
# true if that goal is to be skipped, falsed otherwise.
# Returns the runner self to facilitate chained processing with skip_pages_if, only_pages_if, skip_entry,
# and/or process! if desired.
#
#   skip the 'post_process' goal on each entry of each page processed
#   runner.skip_goal{|goal| goal == 'post_process' }.process!
#
# This is best when used in conjunction with skip_entry to skip_goals for particular entries
# runner.skip_entry{|entry| entry['threshold'] < 2.5 }.skip_goal{|goal| goal == 'post_process' }.process!
#
    def skip_goal(&skip_code)
      @skip_goal_code = skip_code
      self
    end

# Processes configured pages, entries, and goals with a PROC.  The default PROC takes the entry, iterates
# over each goal not skipped by skip_goal, and:
# * determines if an executable #{ @agent_bin }/#{ goal }_agent.rb script exists
# * if so, executes the goal_agent script with commandline arguments constructed from the values in the entry for each field in the query_fields array defined in config.
# If run_in_serial is false, the default PROC runs each agent in the background, in parallel.
# Otherwise, it runs each serially in the foreground.  If dry_run is true, the command is printed to STDERR,
# but is not run.
# A PROC supplied to override the default PROC should take an GoogleDrive::List, and GoogleDrive::Worksheet as arguments.
# This allows the process to query the entry for information using its hash access, and/or update the entry on the
# spreadsheet. In order for changes to the GoogleDrive::List to take effect, the GoogleDrive::Worksheet must be saved in the PROC.
# The process sleeps @sleep_between between each call to the PROC (default or otherwise).  If dry_run is true
# when a PROC is supplied, the page.title and runnable_entry hash inspection are printed to STDERR but the PROC
# is not called.
#
#   # call each goal agent script in agent_bin on each entry in each page
#   runner = SpreadsheetAgent::Runer.new
#   runner.process!
#
#   # find entries with a threshold > 5 and update the 'threshold_exceeded' field
#   runner.skip_entry{|entry| entry['threshold'] <= 5 }.process! do |entry,page|
#     entry.update 'threshold_exceeded', "1"
#     page.save
#
#  # only process entries on the 'main' page where the threshold has not been exceeded
#  runner.only_pages = ['main']
#  runner.skip_entry{|entry| entry['threshold'] != 1 }.process!
#
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

