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

config_file '.clij.rc'
flag [:u, :username], :arg_name => 'user', :desc => 'Jenkins server username'
flag [:p, :password], :arg_name => 'password', :mask => true, :desc => 'Jenkins server password'
flag :i, :arg_name => 'ip_address', :desc => 'Jenkins server IP address', :must_match => /\d+\.\d+\.\d+\.\d+/
flag [:n, :port], :arg_name => 'port_number', :desc => 'Port number used by Jenkins', :default_value => '8080', :must_match => /\d+/
flag [:l, :logname], :arg_name => 'log-file-name', :desc => 'Log all output to log-file-name'
flag [:j, :path], :arg_name => 'path_to_jenkins', :desc => 'Path to Jenkins', :default_value => '/'
flag [:g, :log_level], :arg_name => 'level', :desc => 'Jenkins API Log Levels to view/log', :default_value => 1,
                                                                                            :must_match => { "debug" => 0,
                                                                                                             "info"  => 1,
                                                                                                             "warn"  => 2,
                                                                                                             "error" => 3,
                                                                                                             "fatal" => 4}
flag :header, :arg_name => 'clij message header', :desc => 'Header used by clij to identify its management of a field in Jenkins'
switch :ssl, :desc => 'Use SSL to connect to Jenkins'
switch :o, :desc => 'Send output to STDOUT', :default_value => true, :negatable => true

def check_args?(args,help_msg="job_name is required")
  $log.debug(args)
  if args.nil? || args.empty?
    help_now!(help_msg)
    $log.debug("check_args? returns FALSE")
    return false
  else
    $log.debug("check_args? returns TRUE")
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
        @waldo = Waldo.new
        @waldo.job_list_all
      end
    end  # list all
    list.arg_name 'job_name'
    list.desc 'List all jobs containing job_name'
    list.action do |global_options, options, args|
      if check_args?(args, "job_name is required, or try 'clij job list all'")
        @waldo = Waldo.new(args[0])
        @waldo.job_search_name
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
          @waldo = Waldo.new
          @waldo.all_poll_status
        end
      end  #  poll status all
      status.arg_name 'job_name'
      status.desc 'Show (detailed) infomations regarding the polling used by a job'
      status.switch [:d,:detailed], :desc => 'Provide detailed information on the polling', :default_value => false
      status.switch [:r,:parse], :desc => 'Attempt to provide english description of chrontab format', :defualt_value => false
      status.action do |global_options, options, args|
        if check_args?(args, "job_name is required, or try 'clij job status all'")
          unless options[:detailed]
            request_type = 'basic'
            $log.debug("request_type 'basic'")
          else
            request_type = 'detailed'
            $log.debug("request_type 'detailed'")
          end
          @waldo = Waldo.new(args[0])
          @waldo.job_poll_status(request_type)
          if options[:parse]
            @waldo.parse_trigger_spec  
          end
        end
      end  # poll status job_name
    end #  poll status 
    poll.desc "Revert the most recent clij-caused change to a job's polling data"
    poll.command :revert do |revert|
      revert.action do |global_options, options, args|
        if check_args?(args)
          @waldo = Waldo.new(args[0])
          @waldo.revert_trigger_spec
        end
      end
    end  # poll revert
    poll.arg_name 'job_name "spec"'
    poll.desc 'Write a spec and/or comments to a job.  Old information is backed up automatically.'
    poll.command :write do |write|
      write.action do |global_options, options, args|
        if check_args?(args)
          @waldo = Waldo.new(args.shift)
          spec = args.join(" ")
          @waldo.write_trigger_spec(spec)
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
          if global_options[:log_level] == "debug"
            $log.debug("NOTE: 'clij job discard off all' will not be run while in debug mode.")
            $log.debug("skipped method:  all_discard_off()")
          else
            @waldo = Waldo.new
            #@waldo.all_discard_off
          end
        end
      end  # discard off all
      off.action do |global_options, options, args|
        if check_args?(args, "job_name is required or try 'clij job discard off all'")
          @waldo = Waldo.new(args[0])
          @waldo.job_discard_off
        end
      end  # discard off
    end
    discard.arg_name '[all|job_name] [<days_to_keep>] [<max_num_to_keep> <artifacts_days> <artifacts_max_num_builds>]'
    discard.command :on do |on|
      on.desc 'Activate the discarding of old builds'
      on.command :all do |all|
        all.action do |global_options, options, args|
          if global_option[:log_level] == "debug"
            $log.debug("NOTE:  'clij job discard on all' will not be run while in debug mode.")
          else
            @waldo = Waldo.new
            #@waldo.all_discard_on(...)
          end
        end
      end  # discard on all
      on.action do |global_options, options, args|
        if check_args?(args, "job_name is required")
          @waldo = Waldo.new(args.shift)
          unless args.empty?
            daystokeep = args.shift
            unless args.empty?
              numtokeep = args.shift
              unless args.empty?
                artifactdaystokeep = args.shift
                unless args.empty?
                  artifactnumtokeep = args.shift
                  @waldo.job_discard_on(daystokeep, numtokeep, artifactdaystokeep, artifactnumtokeep)
                else
                  @waldo.job_discard_on(daystokeep, numtokeep, artifactdaystokeep)
                end
              else
                @waldo.job_discard_on(daystokeep, numtokeep)
              end
            else
              @waldo.job_discard_on(daystokeep)
            end
          else
            @waldo.job_discard_on
          end
        end
      end  # discard on <job>
    end  # job discard on
  end  # job discard
  c.desc 'View details about or manipulate build retention'
  c.command :build do |build|
    build.command :status do |status|
      status.arg_name 'job_name'
      status.desc 'Show details regarding the build retention of a job'
      status.action do |global_options, options, args|
        if check_args?(args)
          @waldo = Waldo.new(args[0])
          @waldo.job_build_status
        end
      end
    end  # build status
  end  # build
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
  when 0
    return Logger::DEBUG
  when 1
    return Logger::INFO
  when 2
    return Logger::WARN
  when 3
    return Logger::ERROR
  when 4
    return Logger::FATAL
  else
    return Logger::INFO
  end
end

pre do |global,command,options,arg|
  $log = Logger.new(STDOUT)
  client_opts = get_client_opts(global)
  unless client_opts.has_key?(:msg_header) && client_opts[:msg_header].nil? == false
    $CLIJ_MSG_HEADER = "### WARNING: This field is being managed, in part, by clij.\n### Manual changes are discouraged.\n"
  else
    $CLIJ_MSG_HEADER = client_opts[:msg_header]
  end
  $log.level = get_logging_level(global)
  $log.info("LOG LEVEL SET TO: #{$log.level}")
  p global[:log_level]
  if global[:logname]
    $log.attach(global[:logname])
    client_opts[:log_location] = global[:logname]
  end
  $log.debug("Global options; #{global}")
  $log.debug("Options:  #{options}")
  $log.debug("Client options: #{client_opts}")
  $client = JenkinsApi::Client.new(client_opts)
end
exit run(ARGV)
