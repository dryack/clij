#! /usr/local/opt/ruby193/bin/ruby
# *sigh*

require 'jenkins_api_client'
require 'yaml'
require 'net/https'
require 'cron2english'
require 'gli'
require './Logd'
require './clij-lib'

include GLI::App

program_desc 'Manage Jenkins via command line'
subcommand_option_handling :normal
sort_help :manually

config_file './.clij.rc'
flag [:u, :username], :arg_name => 'user', :desc => 'Jenkins server username'
flag [:p, :password], :arg_name => 'password', :mask => true, :desc => 'Jenkins server password'
flag :i, :arg_name => 'ip_address', :desc => 'Jenkins server IP address', :must_match => /\d+\.\d+\.\d+\.\d+/
flag [:n, :port], :arg_name => 'port_number', :desc => 'Port number used by Jenkins', :default => '8080', :must_match => /\d+/
flag [:l, :logname], :arg_name => 'log-file-name', :desc => 'Log all output to log-file-name'
flag [:j, :path], :arg_name => 'path_to_jenkins', :desc => 'Path to Jenkins', :default => '/'
flag [:g, :log_level], :arg_name => 'level', :desc => 'Jenkins API Log Levels to view/log', :default=>'info',
                                                                                            :must_match => { "debug" => 1,
                                                                                                             "info"  => 2,
                                                                                                             "warn"  => 3,
                                                                                                             "error" => 4,
                                                                                                             "fatal" => 5}
flag :header, :arg_name => 'clij message header', :desc => 'Header used by clij to identify its management of a field in Jenkins'
switch :ssl, :desc => 'Use SSL to connect to Jenkins'
switch :o, :desc => 'Send output to STDOUT', :default_value => true, :negatable => true

def check_args(args,help_msg="job_name is required")
  @log.debug(args)
  if args.nil? || args.empty?
    help_now!(help_msg)
    return false
  else
    return true
  end
end

desc 'Work with jobs'
long_desc 'View information on or manipulate settings of jobs'
command :job do |c|
  c.desc 'List/find jobs managed by Jenkins'
  c.command :list do |list|
    list.desc 'List all jobs on the server'
    list.command :all do |all|
      all.action do |global_options, options, args|
        job_list_all()
      end
    end  # list all
    list.arg_name 'job_name'
    list.desc 'List all jobs containing job_name'
    list.action do |global_options, options, args|
      if check_args(args, "job_name is required, or try 'clij job list all'")
        job_search_name(args[0])
      end
    end  # list <search>
  end  # list
  c.desc 'View details about or manipulate job polling'
  c.command :poll do |poll|
    poll.arg_name 'job_name'
    poll.desc 'Examine the polling status of jobs'
    poll.command :status do |status|
      status.desc 'Print whether polling is enabled for each job on the server -- WARNING:  This is likely to fail on overburdened servers.'
      status.command :all do |all|
        all.action do |global_options, options, args|
          all_poll_status()
        end
      end  #  poll status all
      status.arg_name 'job_name'
      status.desc 'Show (detailed) infomations regarding the polling used by a job'
      status.switch [:d,:detailed], :desc => 'Provide detailed information on the polling', :default_value => false
      status.switch [:r,:parse], :desc => 'Attempt to provide english description of chrontab format', :defualt_value => false
      status.action do |global_options, options, args|
        if check_args(args, "job_name is required, or try 'clij job status all'")
          unless options[:detailed]
            request_type = 'basic'
            @log.debug("request_type 'basic'")
          else
            request_type = 'detailed'
            @log.debug("request_type 'detailed'")
          end
          job_poll_status(args[0], request_type)
          if options[:parse]
            parse_trigger_spec(args[0])  
          end
        end
      end  # poll status job_name
    end #  poll status 
    poll.arg_name 'job_name'
    poll.desc 'Backup the current polling information for job_name'
    poll.command :backup do |backup|
      backup.action do |global_options, options, args|
        if check_args(args)
          backup_trigger_spec(arg[0])
        end
      end
    end  # poll backup
    poll.desc "Revert the most recent clij-caused change to a job's polling data"
    poll.command :revert do |revert|
      revert.action do |global_options, options, args|
        if check_args(args)
          job_poll_revert(args[0])
        end
      end
    end  # poll revert
    poll.arg_name 'job_name "spec"'
    poll.desc 'Write a spec and/or comments to a job.  Old information is backed up automatically.'
    poll.command :write do |write|
      write.action do |global_options, options, args|
        if check_args(args)
          job_name = args.shift
          spec = args.join(" ")
          write_trigger_spec(job_name, spec)
        end
      end
    end  # poll write
  end  # poll
  c.desc "Toggle the 'Discard Old Builds' checkbox and/or manipulate its settings"
  c.command :discard do |discard|
    discard.arg_name '[all|job_name]'
    discard.command :off do |off|
      off.desc 'Shut off the discarding of the old build'
      off.command :all do |all|
        all.action do |global_options, options, args|
          puts "DO SOMETHING HERE SOMEDAY"
        end
      end  # discard off all
      off.action do |global_options, options, args|
        if check_args(args, "job_name is required or try 'clij job discard off all'")
          job_name = args[0]
          puts "DO SOMETHING HERE SOMEDAY"
        end
      end  # discard off
    end
    discard.arg_name '[all|job_name] [<days_to_keep>] [<max_num_to_keep> <artifacts_days> <artifacts_max_num_builds>]'
    discard.command :on do |on|
      on.desc 'Activate the discarding of old builds'
      on.command :all do |all|
        all.action do |global_options, options, args|
          puts "DO SOMETHING HERE SOMEDAY"
        end
      end  # discard on all
      on.action do |global_options, options, args|
        if check_args(args, "job_name is required")
          job_name = args.shift
          unless args.empty?
            daysToKeep = args.shift
            unless args.empty?
              numToKeep = args.shift
              unless args.empty?
                artifactDaysToKeep = args.shift
                unless args.empty?
                  artifactNumToKeep = args.shift
                end
              end
            end
          end
        end
        puts "DO SOMETHING HERE SOMEDAY"
      end  # discard on <job>
    end  # job discard on
  end  # job discard
end  # job


#  Spits out configuration information
#  in the format expected by Jenskin::Client
def get_client_opts(global)
  client_opts = {
    :server_ip => global[:i],
    :server_port => global[:port],
    :jenkins_path => global[:path],
    :username => global[:username],
    :password => global[:password],
    :ssl => global[:ssl],
    :log_level => global[:log_level],
    :msg_header => global[:header]
  }
  return client_opts
end

#  Needed because we've got two logger
#  objects, only one of which is under
#  our direct control.  meh
def get_logging_level(global)
  case global[:log_level]
  when 1
    return Logger::DEBUG
  when 2
    return Logger::INFO
  when 3
    return Logger::WARN
  when 4
    return Logger::ERROR
  when 5
    return Logger::FATAL
  else
    return Logger::INFO
  end
end

pre do |global,command,options,arg|
  config_file '.clij.rc'
  @log = Logger.new(STDOUT)
  @log.level = get_logging_level(global)
  client_opts = get_client_opts(global)
  if global[:logname]
    @log.attach(global[:logname])
    client_opts[:log_location] = global[:logname]
  end
  unless client_opts.has_key?(:msg_header)
    @CLIJ_MSG_HEADER = "### WARNING: This field is being managed, in part, by clij.\n### Manual changes are discouraged.\n"
  else
    @CLIJ_MSG_HEADER = client_opts[:msg_header]
  end
  @log.debug("Global options; #{global}")
  @log.debug("Options:  #{options}")
  @log.debug("Client options: #{client_opts}")
  @client = JenkinsApi::Client.new(client_opts)
end
exit run(ARGV)
