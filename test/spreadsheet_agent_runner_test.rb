require 'test/unit'
require 'shoulda/context'
require 'spreadsheet_agent'
require 'spreadsheet_agent/runner'
require 'capture_io'

class TC_SpreadsheetAgentRunnerTest < Test::Unit::TestCase

  context 'Runner' do

    setup do
      @config_file = File.expand_path(File.dirname( __FILE__ )) + '/../config/agent.conf.yml'

      unless File.exists? @config_file
        $stderr.puts "You must create a valid test Google Spreadsheet and a valid #{ @config_file } configuration file pointing to it to run the tests. See README.txt file for more information on how to run the tests."
        exit
      end
      @test_agent_bin = find_bin() + 'agent_bin'
      @testing_pages = nil
      @agent_scripts = nil
    end

    teardown do
      runner = SpreadsheetAgent::Runner.new(:agent_bin => @test_agent_bin, :config_file => @config_file)
      if runner.db.worksheet_by_title('testing').nil?
        tpage = runner.db.add_worksheet('testing')
        tpage.max_rows = 2
        tpage.save
      end
      unless @testing_pages.nil?
        @testing_pages.each do |testing_page|
          testing_page.delete
        end
      end
      agent_scripts_executable(false)
    end

    context 'instantiated' do

     should 'be a SpreadsheetAgent::Runner' do
        runner = SpreadsheetAgent::Runner.new(:config_file => @config_file)
        assert_not_nil runner, 'runner is nil!'
        assert_instance_of(SpreadsheetAgent::Runner, runner)
      end

    end #instantiated

    context 'agent_bin' do

      should 'have a sensible default' do
        expected_agent_bin = File.expand_path(File.dirname( $0 )) + '/../agent_bin'
        runner = SpreadsheetAgent::Runner.new(:config_file => @config_file)
        assert_equal expected_agent_bin, runner.agent_bin
      end

      should 'be overridable on construction' do
        runner = SpreadsheetAgent::Runner.new(:agent_bin => @test_agent_bin, :config_file => @config_file)
        assert_equal @test_agent_bin, runner.agent_bin
      end

    end #agent_bin

    context 'agent scripts' do

      setup do
        @entries = {'dotest' => false, 'donottest' => false }
        @headers = ['testentry', 'testpage', 'ready', 'testgoal', 'othergoal', 'complete']
        @runner = prepare_runner(
                                 ['foo_page', 'bar_page'],
                                 @headers,
                                 @entries
                                 )
      end

      should 'pass tests' do
        #should 'not run if scripts in agent_bin are not executable' do
        reset_testing_pages(@testing_pages,true)
        @testing_pages.each do |page|
          page.reload
          page.rows(1).each do |entry|
            assert_equal 1, entry[2].to_i
          end
        end
        agent_scripts_executable(false)
          
        Dir.glob("#{  @test_agent_bin }/*.rb") do |rb_file|
          assert !File.executable?(rb_file), "#{ rb_file } should not be executable"
        end
        
        @runner.process!

        @testing_pages.each do |page|
          page.reload
          page.rows(1).each do |entry|
            assert entry[3].nil? || entry[3].empty?, "entry #{ entry[0] } should not have run!: #{ entry.inspect }"
            assert entry[4].nil? || entry[3].empty?, "entry #{ entry[0] } should not have run!: #{ entry.inspect }"
          end
        end

        #should not run on entries that are not ready
        reset_testing_pages(@testing_pages)
        agent_scripts_executable(true)
        @testing_pages.each do |page|
          page.rows(1).each do |entry|
            assert entry[2].to_i != 1, "entry #{ entry[0] } should not be ready!: #{ entry.inspect }"
          end
        end
        
        @runner.process!
        sleep 2

        @testing_pages.each do |page|
          page.reload
          page.rows(1).each do |entry|
            assert entry[3].to_i != 1, "entry #{ entry[0] } should not have run!: #{ entry.inspect }"
          end
        end

        # should 'if executable, run for each goal of each ready entry by default' do
        reset_testing_pages(@testing_pages,true)
        
        @runner.process!
        sleep 5
        @testing_pages.each do |page|
          page.reload
          page.rows(1).each do |entry|
            assert_equal "1", entry[4]
          end
        end

        # should 'allow code to be passed to override default process! function' do
        reset_testing_pages(@testing_pages, true)
        expected_to_run = {}
        @testing_pages.each do |page|
          expected_to_run[page.title] = {}
          (2..page.num_rows).to_a.each do |rownum|
            expected_to_run[page.title][page[rownum,1]] = false
          end
          page.save
        end
        
        @runner.process! do |ran_entry, ran_page|
          ran_entry.update 'testgoal' => "1"
          ran_page.save
          expected_to_run[ran_page.title][ran_entry['testentry']] = true
        end
        sleep 2
        
        @testing_pages.each do |page|
          page.reload
          page.rows(1).each do |entry|
            assert_equal "1", entry[2]
            assert_equal "1", entry[3]
            assert expected_to_run[page.title][entry[0]], "#{ page.title } should have been processed on #{ entry[0] }"
          end
        end

        # should 'allow code passed to override default process! function to update fields on each entry' do
        reset_testing_pages(@testing_pages, true)

        @runner.process! do |ran_entry, ran_page|
          ran_entry.update 'complete' => "1"
          ran_page.save
        end
        sleep 2
        
        @testing_pages.each do |page|
          page.reload
          page.rows(1).each do |entry|
            assert_equal "1", entry[5]
          end
        end

        # should 'not print anything to STDERR if debug is not set to true' do
        reset_testing_pages(@testing_pages, true)

        nothing_output = CaptureIO.new
        nothing_output.start
        @runner.process! do |re, rp|
          re.update 'othergoal' => "1"
          rp.save
        end
        nothing_captured = nothing_output.stop
        assert nothing_captured[:stderr].length < 1, 'should not have captured any stderr'
        @testing_pages.each do |page|
          page.reload
          page.rows(1).each do |entry|
            assert_equal "1", entry[4]
          end
        end

        # should 'allow debug to be set and print output to STDERR' do
        reset_testing_pages(@testing_pages, true)
        @runner = SpreadsheetAgent::Runner.new(:agent_bin => @test_agent_bin, :debug => true, :config_file => @config_file)
        assert @runner.debug, 'debug should be true'
        debug_output = CaptureIO.new
        debug_output.start
        @runner.process! do |re, rp|
          re.update 'testgoal' => "1"
          rp.save
        end
        debugged_output = debug_output.stop
        assert debugged_output[:stderr].length > 0, "should have captured stderr in debug mode"
        sleep 2        
        @testing_pages.each do |page|
          page.reload
          page.rows(1).each do |entry|
            assert_equal "1", entry[3]
          end
        end

        # should 'allow dry_run to be set, and not run any entries, but set debug to true' do
        reset_testing_pages(@testing_pages, true)
        @runner = SpreadsheetAgent::Runner.new(:agent_bin => @test_agent_bin, :dry_run => true, :config_file => @config_file)
        assert @runner.debug, 'debug should be true with dry run'

        dry_output = CaptureIO.new
        dry_output.start
        @runner.process! do |re, rp|
          re.update 'testgoal' => "1"
          rp.save
        end
        captured_dry_output = dry_output.stop
        assert captured_dry_output[:stderr].length > 0, 'should have captured stderr in debug mode'
        sleep 2
        @testing_pages.each do |page|
          page.reload
          page.rows(1).each do |entry|
            assert entry[3].nil? || entry[3].empty?, "#{ page.title } should not have run #{ entry[0] } #{ entry.inspect }"
          end
        end

        # should 'allow sleep_between to be set, and sleep that amount between process for each entry' do
        reset_testing_pages(@testing_pages, true)
        expected_time_between = 10
        @runner = SpreadsheetAgent::Runner.new(:agent_bin => @test_agent_bin, :sleep_between => expected_time_between,:config_file => @config_file)

        beginning_time = Time.now
        first_time = true
        @runner.process! do |re, rp|
          if first_time
            first_time = false
          else
            elapsed_time = Time.now - beginning_time
            assert_equal expected_time_between, elapsed_time.to_i
          end
          re.update 'testgoal' => "1"
          rp.save
          beginning_time = Time.now          
        end
        sleep 2
        
        @testing_pages.each do |page|
          page.reload
          page.rows(1).each do |entry|
            assert_equal "1", entry[3]
          end
        end

        #should 'allow skip_entry to be set with code, and only process entries that return false from the code when passed the entry' do
        reset_testing_pages(@testing_pages, true)

        @runner.skip_entry do |entry|
          (entry['testentry'] == 'donottest')
        end

        @runner.process! do |ran_entry, ran_page|
          ran_entry.update 'testgoal' => "1"
          ran_page.save
        end
        sleep 2        
        @testing_pages.each do |page|
          page.reload
          page.rows(1).each do |entry|
            if entry[0] == 'donottest'
              assert entry[3].nil? || entry[3].empty?, "#{  page.title } #{ entry[0]} should not have run"
            else
              assert_equal "1", entry[3]
            end
          end
        end

        # should 'allow skip_goal to be set with code, and only process goals for each entry that return false from the code when passed the goal' do
        reset_testing_pages(@testing_pages, true)

        @runner.skip_goal { |goal|
          if goal == 'othergoal'
            return true
          else
            return false
          end
        }.process!
        sleep 2
        @testing_pages.each do |page|
          page.reload
          page.rows(1).each do |entry|
            assert entry[3] == "1", "entry #{ entry[0] } should have run testgoal #{ entry.inspect }"
            assert entry[4].nil? || entry[4].empty?, "othergoal should not have run for any entry #{ entry.inspect }"
          end
        end

        #should 'allow only_pages to be set and only process @only_pages' do
        @test_only_pages = ['foo_page', 'baz_page']
        @runner = SpreadsheetAgent::Runner.new(:agent_bin => @test_agent_bin, :only_pages => @test_only_pages, :config_file => @config_file)
        @testing_pages.push(add_page_to_runner(@runner, 'baz', @headers, @entries))


        expected_to_run = {}
        @testing_pages.each do |page|
          expected_to_run[page.title] = @test_only_pages.include? page.title
        end
        
        @runner.process! do |ran_entry, ran_page|
          ran_entry.update 'complete' => "1"
          ran_page.save
          assert expected_to_run[ran_page.title], "#{ ran_page.title } is not in #{ @test_only_pages.inspect }!"
        end
        
        @testing_pages.select { |page| @test_only_pages.include? page.title }.each do |page|
          page.reload
          page.rows(1).each do |entry|
            assert_equal "1", entry[5]
          end
        end

        #should 'allow only_pages_if to be set and only process those pages' do
        @runner = SpreadsheetAgent::Runner.new(:agent_bin => @test_agent_bin,:config_file => @config_file)
        reset_testing_pages(@testing_pages, true)
        
        @runner.only_pages_if{ |title|
          if title.match('ba*')
            return true
          else
            return false
          end
        }.process! do |ran_entry, ran_page|
          ran_entry.update 'complete' => "1"
          ran_page.save
          assert ran_page.title.match('ba*'), "#{ ran_page.title } was not expected to run!"
        end
        
        @testing_pages.select { |page| page.title.match('ba*') }.each do |page|
         page.reload 
         page.rows(1).each do |entry|
            assert_equal "1", entry[5]
          end
        end

        #should 'allow skip_pages to be set and only process pages not in @skip_pages' do
        @test_skip_pages = ['foo_page', 'baz_page']
        @runner = SpreadsheetAgent::Runner.new(:agent_bin => @test_agent_bin, :skip_pages => @test_skip_pages,:config_file => @config_file)
        reset_testing_pages(@testing_pages, true)
        expected_to_run = {}
        @testing_pages.each do |page|
          expected_to_run[page.title] = !( @test_skip_pages.include? page.title )
        end
        
        @runner.process! do |ran_entry, ran_page|
          ran_entry.update 'complete' => "1"
          ran_page.save
          assert expected_to_run[ran_page.title], "#{ ran_page.title } is in #{ @test_skip_pages.inspect }!"
        end
        
        @testing_pages.each do |page|
          page.reload
          if @test_skip_pages.include?(page.title)
            should_equal = nil
          else
            should_equal = "1"
          end
          page.rows(1).each do |entry|
            assert_equal should_equal, entry[4]
          end
        end

        #should 'allow skip_pages_if to be set and only process pages not skipped by the code' do
        @runner = SpreadsheetAgent::Runner.new(:agent_bin => @test_agent_bin,:config_file => @config_file)
        reset_testing_pages(@testing_pages, true)
        
        @runner.skip_pages_if { |title|
          title.match('ba*')
        }.process! do |ran_entry, ran_page|
          ran_entry.update 'complete' => "1"
          ran_page.save
          assert !( ran_page.title.match('ba*') ), "#{ ran_page.title } was not expected to run!"
        end
        
        @testing_pages.reject { |page| page.title.match('ba*') }.each do |page|
          page.reload
          page.rows(1).each do |entry|
            assert_equal "1", entry[5]
          end
        end

      end #pass tests

    end #agent script executable

  end #Runner

  def find_bin()
    File.expand_path(File.dirname( __FILE__ )) + '/'
  end

  def prepare_runner(pages, headers, entries)
    runner = SpreadsheetAgent::Runner.new(:agent_bin => @test_agent_bin,:config_file => @config_file)
    @testing_pages = []
    
    pages.each do |page|
      @testing_pages.push(add_page_to_runner(runner, page, headers, entries))
    end
    testing_page = runner.db.worksheet_by_title('testing')
    unless testing_page.nil?
      testing_page.delete
    end

    runner
  end

  def add_page_to_runner(runner, page, headers, entries)
    testing_page = runner.db.worksheet_by_title(page)
      if testing_page.nil?
        testing_page = runner.db.add_worksheet(page)
      else
        testing_page.max_rows = 1
      end
      
      colnum = 1
      headers.each do |field|
        testing_page[1,colnum] = field
        colnum += 1
      end
      entry_row = 2
      entries.each do |entry, ready|
        testing_page[entry_row,1] = entry
        testing_page[entry_row,2] = page
        testing_page[entry_row,3] = "1" if ready
        entry_row += 1
        
      end
      testing_page.max_rows = entry_row
      testing_page.save
      testing_page
  end

  def agent_scripts_executable(set_executable)
    if set_executable
      `chmod 700 #{  @test_agent_bin }/*.rb`
    else
      `chmod 600 #{  @test_agent_bin }/*.rb`
    end
  end

  def reset_testing_pages(testing_pages, ready = false)
    ready_value = ready ? "1" : nil

    testing_pages.each do |page|
      (2..page.num_rows).to_a.each do |rownum|
        page[rownum,3] = ready_value
        page[rownum,4] = nil
        page[rownum,5] = nil
        page[rownum,6] = nil
      end
      page.save
    end
  end

end #TC_SpreadsheetAgentRunnerTest
