require 'spreadsheet_agent/agent'
require 'spreadsheet_agent/error'
require 'spreadsheet_agent/db'
require 'spreadsheet_agent/runner'
require 'socket'
require 'open3'
require 'capture_io'
require 'mail'

# @note The license of this source is "MIT Licence"
# A Distributed Agent System using Google Spreadsheets
#
# SpreadsheetAgent is a framework for creating massively distributed pipelines
# across many different servers, each using the same google spreadsheet as a
# control panel.  It is extensible, and flexible.  It doesnt specify what
# goals any pipeline should be working towards, or which goals are prerequisites
# for other goals, but it does provide logic for easily defining these relationships
# based on your own needs.  It does this by providing a subsumption architecture,
# whereby many small, highly focused agents are written to perform specific goals,
# and also know what resources they require to perform them.  Agents can be coded to
# subsume other agents upon successful completion.  In addition, it is
# designed from the beginning to support the creation of simple human-computational
# workflows.
#
# SpreadsheetAgent requires GoogleDrive[http://rubygems.org/gems/google_drive], and works with a Google Spreadsheet with some or all worksheets
# formatted according to the following:
# * The top row of a page to be processed has fields for all entry record in subsequent rows
# * You can define any fields necessary, but you must specify a 'ready' and a 'complete' field
# * You must define at least 1 key field, and the key field must be specified as required in the :config (see SpreadsheetAgent::Db)
# * You should then define fields named for agent_bin/#{ field_name }_agent.rb for each agent that you plan to deploy in your pipeline
# @version 0.01
# @author Darin London Copyright 2013
module SpreadsheetAgent
end
