spreadsheet_agent
=================

SpreadsheetAgent is a framework for creating massively distributed pipelines
across many different servers, each using the same google spreadsheet as a
control panel.  It is extensible, and flexible.  It doesnt specify what
goals any pipeline should be working towards, or which goals are prerequisites
for other goals, but it does provide logic for easily defining these relationships
based on your own needs.  It does this by providing a subsumption architecture,
whereby many small, highly focused agents are written to perform specific goals,
and also know what resources they require to perform them.  In addition, it is
designed from the beginning to support the creation of simple human-computational
workflows.

Subsumption Architecture
------------------------

Subsumption architectures were developed within the Robotics and AI communities
beginning in the 50s (1, 2, 3).  Recently, the success of the Mars Rover mission
demonstrated the flexibility and strength of the subsumption architecture. There 
are many subsumption architecture packages available, such as the Algernon (4)
system written using the Java(tm) Simbad robotics platform.

One of the core ideas of a subsumption architecture is that of creating lots of
small, loosely coordinated autonomous agents.  Each agent is designed to respond
to a specific set of inputs to produce a specific set of outputs.  Some agents
are able to override the inputs, and/or outputs of other agents, but this is
very limited.  There is no central processing agent that knows everything about
all other agents.  Each agent represents a small, reusable chunk of expertise,
much like an object in object oriented programming.

In this system, agents should be written to recieve a defined set of input 
arguments, and perform a specific data manipulation task, called a 'goal',
on the data defined by these inputs.  Furthermore, each agent should be 
loosely coordinated to work together nicely with other agents (potentially)
running on the same node using the subsumption architecture.  As long as agents
work and play nicely with each other on the same node, it is possible to deploy
the same Google-Spreadsheet-Agent implementation on many different nodes.

Google Spreadsheet
------------------

This system is designed to work with a single Google Spreadsheet which has
one or more pages designed with the same, simple format.  The first row on
a page should define the field names for each column, and each subsequent
row should define the specific values for these fields on a single record.
When [GoogleDrive](https://github.com/gimite/google-drive-ruby) returns the
rows on this kind of page, it returns a Hash for each record, with the column
names as keys.

There are 3 kinds of fields which must be represented in a
spreadsheet page.

* keys: These fields are used to find specific records, like a database
           table key.  Some keys are optional, but there must be at least
           one required key field for any google agents implementation.

* goals: These fields are tasks to be completed for each record.

* ready and complete: Every page should define fields named 'ready' and
     'complete'.  When an agent attempts to run a job for a particular record,
     it will skip the job if that particular dataset is not ready (lacks a 1 in
     the 'ready' field  on the record), or if all goals are completed (has a 1
     in the 'complete' field on the record).

In addition, a spreadsheet page can define any number of fields that are used
for other purposes, such as

* communicating other data needed by the agents tied to its goals
* allowing agents to communicate information back to the page for other agents
* providing information to human agents that might want to read the spreadsheet
as well.

Each SpreadsheetAgent implementation should be defined around the same spreadsheet
architecture, e.g. all of its agents should use the same spreadsheet (regardless of the
number of pages defined in the spreadsheet), and each page in the spreadsheet should
have the same key field or fields represented.  The key fields should be generalized
to provide the information required to pull out a specific record on a specific page.
If one or more pages have 3 required key fields, but one page only requires 2 of those
3 fields for its tasks, then the 3rd field can be optional at the implementation level,
but that page must define the field and leave it blank for all records.  This is important
for the runners to function (see below), as they may be provided only with a set of 
values for the defined set of keys, and need to be able to use these values (even
if null) in a query for a specific record.

Human-computationall workflows
------------------------------

Certain fields on a particular spreadsheet may be setup to require human agents
to set their values.  Computational agents may be designed to depend on these fields
to be set to some value before they can run, or otherwise use data in these fields
for their processing.  This sets up a very intuitive, easy to understand workflow
system whereby humans and computational agents work together to achieve the goals
for a particular project.

Components
----------
* Agents:  A SpreadsheetAgent::Agent is a small script designed to accomplish a specific goal for a specific set
of key values defining a single record on a page. 

* Runners:  Runners are scripts designed to be fed an ordered set of key fields and goals to be worked
on.  SpreadsheetAgent::Runner is a framework for creating these programs which
programmatically work through some or all pages in a Google Spreadsheet, and run some or
all of the possible entry-goals on a particular compute node.  Using cron, or some other scheduling
software, a well designed system of different runner scripts can be created which will
attempt goals for every record of every page until they are all completed over time, but
can use plans of some sort (simple collections of key-goal records) to temporarily influence
the order in which these key-goal jobs are attempted, opportunistically.  Agents and runners
can then be spread onto multiple nodes to work in a coordinated fashion to accomplish the tasks
specified on the same Google Spreadsheet.  This begins to approach one of the goals of
subsumption programming, the concept of using plans instead of programs to define and
prioritize a large, complex set of tasks to be completed (3).

Examples
---------

The following scenarios all use a series of ruby scripts named for specific tasks
(e.g. basename $0 =~ s/\.*$// returns the agent_name) located in a single directory,
with their executable bits set.  A runner is used which scans through the configured
google spreadsheet looking for fields tied to executable scripts in dir (e.g. -x $dir/$name)
and runs them with the configured key_field arguments.  This runner is configured to run in
cron every hour on 6 different servers with the same script directory, and datafiles 
made available using NFS.

* Basic Pipeline
Five scripts need to run:
  - taskA
  - taskB
  - taskC
  - taskD
  - taskE

taskB and taskC require taskA to have finished for an entry before they
can run, but can then run in parallel on different servers. taskD requires
taskC, and taskE requires taskB and taskD to have run (e.g. it needs all tasks
to have been completed for a given record).

taskB and taskC cannot run together on the same machine at the same time.

google spreadsheet is setup with fields:

arg1 arg2 ready taskA taskB taskC taskD taskE complete

and 3 arg1 entries:
foo
bar
baz

taskA:

    require 'spreadsheet_agent/agent'

    arg1 = ARGV[1]
    google_page = 'page'
    google_agent = SpreadsheetAgent::Agent.new(
                                          agent_name: 'taskA',
                                          page_name: google_page,
                                          debug: true,
                                          max_selves: 4, 
                                          bind_key_fields: {
                                               'arg1': arg1
                                          }
                                          )

    google_agent.process! do |event|
      begin
        # ... do taskA stuff
      rescue error
        $stderr.puts "THERE WAS AN ERROR"
        return false
      end
      return true
    end

taskB:

    require 'spreadsheet_agent/agent'

    arg1 = ARGV[1]
    google_page = 'page'
    google_agent = SpreadsheetAgent::Agent.new(
                                                agent_name:  'taskB',
                                                page_name:  google_page,
                                                debug:  true,
                                                max_selves:  3, 
                                                bind_key_fields:  {
                                                   'arg1':  arg1
                                                },
                                                prerequisites:  [ 'taskA' ],
                                                conflicts_with:  {
                                                                 'taskC':  1,
                                                               }
                                              )

    google_agent.process! do |event|
      begin
        # ... do taskB stuff
      rescue error
        $stderr.puts "THERE WAS AN ERROR"
        return false
      end
      return true
    end

taskC:

    require 'spreadsheet_agent/agent'

    arg1 = ARGV[0]
    google_page = 'page'
    google_agent = SpreadsheetAgent::Agent.new(
                                                agent_name:  'taskC',
                                                page_name:  google_page,
                                                debug:  true,
                                                max_selves:  4, 
                                                bind_key_fields:  {
                                                   'arg1':  arg1
                                                },
                                                prerequisites:  [ 'taskA' ],
                                                conflicts_with:  {
                                                             'taskB':  1,
                                                }
                                              )
    google_agent.process! do |event|
      begin
        # ... do taskD stuff
      rescue error
        $stderr.puts "THERE WAS AN ERROR"
        return false
      end
      return true
    end

taskD:

    require 'spreadsheet_agent/agent'

    arg1 = ARGV[0]
    google_page = 'page'
    google_agent = SpreadsheetAgent::Agent.new(
                                                agent_name:  'taskD',
                                                page_name:  google_page,
                                                debug:  true,
                                                max_selves:  1, 
                                                bind_key_fields:  {
                                                  'arg1':  arg1
                                                },
                                                prerequisites:  [ 'taskC' ]
                                              );

    google_agent.process! do |event|
      begin
        # ... do taskD stuff
      rescue error
        $stderr.puts "THERE WAS AN ERROR"
        return false
      end
      return true
    end

taskE:

    require 'spreadsheet_agent/agent'
  
    arg1 = ARGV[0]
    google_page = 'page'
    google_agent = SpreadsheetAgent::Agent.new(
                                                agent_name:  'taskE',
                                                page_name:  google_page,
                                                debug:  true,
                                                max_selves:  5, 
                                                bind_key_fields:  {
                                                   'arg1':  arg1
                                                },
                                                prerequisites:  [ 'taskB', 'taskD' ]
                                              );

    google_agent.process! do |event|
      begin
        # ... do taskE stuff
      rescue error
        $stderr.puts "THERE WAS AN ERROR"
        return false
      end
      return true
    end

Runner:

   require 'spreadsheet_agent/runner'

   runner = SpreadsheetAgent::Runner->new();
   runner->process!

* Simple Human Computational Workflow

A field called taskA_passes_qc is added to the google spreadsheet.  Code will never write to it,
but a human will see that taskA has run successfully, and view its output to verify that it ran
correctly.  If so, the human will set that field to something 'true' in perl for that record.  If
not, the taskA_passes_qc field is left blank (false).  taskB and taskC are modified to depend on
taskA_passes_qc instead of taskA.

taskA remains as is (or it could add information to field(s) on the spreadsheet to help the
human QC its result).

modified taskB and taskC simply change their google_agent constructor to have:

    google_agent = SpreadsheetAgent::Agent.new(
                                                agent_name:  'taskB', # or taskC for taskC
                                                page_name: google_page,
                                               debug:  true,
                                               max_selves:  3, 
                                               bind_key_fields:  {
                                                 'arg1':  arg1
                                               },
                                               prerequisites:  [ 'taskA_passes_qc' ],
                                               #.....same
                                             );

The rest of the pipeline runs as above.

* Human Computational Workflow where Human can override 'failure'

google spreadsheet is modified to have 'taskCmetricA' and taskCmetricB' fields.
taskC modified to set these back to the google spreadsheet for the record on failure:

    google_agent.process do |entry|
      begin
        # ... do taskC stuff, setting @metric_a and @metric_b
      rescue error
        $stderr.puts "THERE WAS AN ERROR"
        return (false, { 'taskCmetricA':  @metric_a, 'taskCmetricB':  @metric_b }    )
      end
      return true
    end

Human sees that taskC has failed for a specific record, but decides that metricA and metricB
are sufficient to override the failure to a 1 for taskC.  This allows taskD to run as planned.

There are many more combinations that can be utilized here.

There are also different runners possible.  You can set up a page on the spreadsheet that
is for prioritization.  This will have the key_fields represented, but will not have a ready
flag, so the normal runner will just skip over all the entries on this page and proceed to
the next page or pages.  The normal runner can be modified to run less often in cron, while
the priority runner can run 4 times per hour in cron.  A human can then place things in the
priority queue that need to run at higher priority than the others, but the normal runner can
still attempt to launch processes that are needing to be run but are not high priority, and
let the subsumption rules determine whether these can run or not on any given machine.

Basic Runner:

    require 'spreadsheet_agent/runner'

    # the basic runner should not process the page named priority
    runner = SpreadsheetAgent::Runner.new('skip_pages':  [ 'priority' ]);
    runner.process!

Priority Page Runner:

    require 'spreadsheet_agent/runner'

    # the priority runner should only process the priority page
    runner = SpreadsheetAgent::Runner.new('only_pages':  [ 'priority' ])
    runner.process!

License
-------

The license of the source is The MIT License (MIT)

Author
------

Darin London

Testing
-------

Most of tests for this module will be skipped unless you configure a test spreadsheet and
corresponding config/agent.conf.yml (use config/test.agent.conf.yml.tmpl as a template)
file to work with it.

The test spreadsheet must have a single page in it, called 'testing', the tests will
add and remove all other fields and pages that are required to run.  One important thing
to note is that it is possible that one or more tests will fail simply due to timing issues
and transient failures when communicating with the Google Spreadsheet service.
Rerunning the tests that have failed should show that they pass.  It is possible to run
the entire suite of tests through to completion, but it may take several runs to accomplish.
For this reason, all tests are skipped on initial installation of the modules using cpan.
If you are installing into a production system, you can set up the testing config and run
the tests manually to verify that they everything works.


References
----------

1. Brooks, Rodney A. 'A Robust Layered Contol System for a Mobile Robot' 
  IEEE Journal of Robotics and Automation, Vol. RA-2, No. 1, March 1986
  pg. 14-23.

2. Brooks, Rodney A., 'Intelligence without representation'
  Artificial Intelligence 47 (1991), pg. 139-159.

3. Agre, P. E., and Chapman, D., 'What are Plans for?'
  In Maes, Pattie, 'Designing Autonomous Agents'
  1990 Elsevier Science Publishers.

4. Algernon: http://sourceforge.net/projects/lemaze/

