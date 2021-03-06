require 'jenkins_api_client'
require 'net/https'
require 'cron2english'
require './Logd'

class Waldo
  
  
  def new(*job)
    initialize(job)
  end
  
  def initialize(*job)
    @DUMP_FILE = ".clij-list.tmp"
    @HOMEDIR = File.expand_path("~")
    $log.debug("\nEntering Waldo::initialize")
    unless job.empty? || job.nil?
      @job = job.pop
      $log.debug("Waldo instance initialized, job = #{@job}")
    else
      $log.debug("Waldo instance initialized")
    end
  end

  def all_poll_status
    $log.debug("\nEntering Waldo::all_poll_status")
    # normal run?
    unless dump_file?
      $log.debug("No dump file found; starting normally")
      job_list = $client.job.list_all
    # did we find a dump_file from an interrupted run?
    else
      job_list = load_dump_file
    end
    # start the job run 
    job_list.each do |job|
      if job == "BASE_JAVA_JOB" || job == "FAMC"
        job_list.delete("BASE_JAVA_JOB")
        job_list.delete("FAMC")
        next
      else
        $log.info("#{@job} => #{$client.job.get_config(job).include?('<spec>')}")
      end
      job_list.shift
      $log.debug("#{job_list[0]}")
    end
  rescue Interrupt 
    recoverable_action(job_list)
  end
  

  def all_poll_off
  # will actually set all to poll once per month, spread out across the month
  # unless overridden?  maybe?
  # probably just call job_poll_change() with a hardcoded approach?
    $log.debug("\nEntering Waldo::all_poll_off")
  end

  def all_poll_revert
  # possibly needed counterpart to above?
    $log.debug("\nEntering Waldo::all_poll_revert")
  end
  
  def job_poll_status(request_type='basic')
  # will check the poll status for a given job:
  # basic:  yes or no
  # detailed:  returns "no" or "yes, <details> <if there are old details that can be
  # reverted to>"
    $log.debug("\nEntering Waldo::job_poll_status")
    doc = config_obtain
    $log.debug("config.xml parsed")
    if request_type == 'detailed'
      if doc.to_s.include?('<spec>')
        $log.info(clean_txt(doc.xpath("//spec")))
      else 
        $log.info "No polling found for job #{@job}"
      end
    elsif request_type.nil? || request_type == 'basic'
      $log.info(doc.to_s.include?('<spec>'))
    else 
      $log.error "Unsupported option in job_poll_status"
    end
  end

  def job_build_status(job)
  # will check to see if 'Discard Old Builds' is checked
  # and if so, the details of the setting(s)
    $log.debug("\nEntering Waldo::job_build_status")
    doc = config_obtain
    $log.debug("config.xml parsed")
    if discard_checkbox?(doc)
      $log.info("days to keep: #{clean_txt(doc.xpath("//daysToKeep"))}")
      $log.info("num to keep: #{clean_txt(doc.xpath("//numToKeep"))}")
      $log.info("artifacts days to keep: #{clean_txt(doc.xpath("//artifactDaysToKeep"))}")
      $log.info("artifacts num to keep: #{clean_txt(doc.xpath("//artifactNumToKeep"))}")
    else
      $log.info "'Discard Old Builds' is not checked for #{@job} (or individual settings remain unset)"
    end
  end

  def write_trigger_spec(spec)
  # will write a spec to <hudson.triggers.SCMTrigger><spec>
    $log.debug("\nEntering Waldo::write_trigger_spec")
    doc = config_obtain
    $log.debug("config.xml parsed")
    if doc.search('spec').empty?
      puts "#{@job} doesn't have polling set in its configuration."
    else
      polling = doc.at_css "spec"
      $log.debug("polling = doc.at_css 'spec'")
      unless polling.content.include?("#{$CLIJ_MSG_HEADER}")
        # 
        $log.debug("No header found")
        polling.content = "#{$CLIJ_MSG_HEADER}\n" + "#{spec}\n\n" + polling.content.split("\n").map {|y| "### " + y}.join("\n")
      else
        $log.debug("Header found")
        split_polling = parsing_spec(polling.content) 
        if split_polling["backedup"].empty?
          # no backed up spec exists - replace header, add new spec, rebuild
          # comments and currently active code
          polling.content.clear
          polling.content = "#{$CLIJ_MSG_HEADER}\n" + "#{spec}\n\n" + split_polling["comments"].map {|y| "### " + y}.join("\n") +
                            "\n" + split_polling["activecode"].map {|y| "### " +y}.join("\n")
        else
          # existing backed up spec in place - we do NOT push down here;
          # replace header, add new spec, replace CURRENT backed up code
          polling.content.clear
          polling.content = "#{$CLIJ_MSG_HEADER}\n" + "#{spec}\n\n" + split_polling["backedup"].join("\n")
        end
      end
      $log.debug("Attempting to POST update to job")
      $client.job.update(@job, doc.to_xml)
    end
  end

  def revert_trigger_spec
  # will revert to the saved poll settings found in the comments, and then delete
  # the programmed comments; returns an error if nothing is found
  # error if none found
    $log.debug("\nEntering Waldo::job_poll_revert")
    doc = config_obtain
    $log.debug("config.xml parsed")
    if doc.search('spec').empty?
      puts "#{@job} is not set up for polling"
    elsif doc.search('spec').grep(/#{$CLIJ_MSG_HEADER}/).empty?
      puts "#{@job} is not being managed by clij, or has already been reverted"
    else
      polling = doc.at_css "spec"
      split_polling = parsing_spec(polling.content)
      if split_polling["backedup"].empty?
        $log.info("No back up trigger spec found!")
        return 0
      else
        polling.content.clear
        polling.content = "#{$CLIJ_MSG_HEADER}\n" + split_polling["backedup"].map {|y| y.gsub("### ", '').join("\n")}
      end 
      $client.job.update(@job, doc.to_xml)
    end
  end

  def parse_trigger_spec
  # will make sense of <hudson.triggers.SCMTrigger><spec>
    $log.debug("\nEntering Waldo::parse_trigger_spec")
    doc = config_obtain
    doc = doc.search('spec').to_s.gsub!(/<\/?spec>/,'')
    unless doc.to_s.empty?
      puts "\n#{@job} polling schedule:"
      doc.each_line.to_a.each do |x|
        unless x.start_with?('#')
          puts x
          puts Cron2English.parse(x.gsub(/H/,'*').gsub(/,0-/,',00-'))
          puts ""
        end
      end
    else
      puts "#{@job} has no polling schedule!"
    end
  end

  def job_discard_off
    $log.debug("\nEntering Waldo::job_discard_off")
    doc = config_obtain
    $log.debug("config.xml parsed")
    if doc.search('logRotator').empty?
      job_discard_create(-1, -1, -1, -1) 
    else
      job_discard_change(-1, -1, -1, -1)
    end
  end

  def job_discard_on(daystokeep, numtokeep, adaystokeep, anumtokeep)
    $log.debug("\nentering Waldo::job_discard_on")
    doc = config_obtain
    $log.debug("config.xml parsed")
    if doc.search('logRotator').empty?
      job_discard_create(daystokeep, numtokeep, adaystokeep, anumtokeep)
    else
      job_discard_change(daystokeep, numtokeep, adaystokeep, anumtokeep)
    end
  end

  def job_discard_change(daystokeep, numtokeep, artifactdaystokeep, artifactnumtokeep)
    $log.debug("\nentering Waldo::job_discard_change")
    doc = config_obtain
    $log.debug("config.xml parsed")
    days = doc.at_css "daysToKeep"
    num = doc.at_css "numToKeep"
    artday = doc.at_css "artifactDaysToKeep"
    artnum = doc.at_css "artifactNumToKeep"
    days.content = daystokeep
    num.content = numtokeep
    artday.content = artifactdaystokeep
    artnum.content = artifactnumtokeep
    $client.job.update(@job, doc.to_xml)
  end

  def all_discard_off()
    $log.debug("\nEntering Waldo::all_discard_off")
    $client.job.list_all.each { |job| job_discard_off(job) }
  end

  def job_discard_create(daystokeep="-1", numtokeep="5", artifactdaystokeep="-1", artifactnumtokeep="-1")
    $log.debug("\nEntering Waldo::job_discard_create")
    doc = config_obtain
    root = doc.root
    $log.debug("config obtained")
    node = Nokogiri::XML::Node.new('logRotator', root)
    $log.debug("node logRotator created")
    node_days_to_keep = Nokogiri::XML::Node.new('daysToKeep', root)
    $log.debug("node logRotator child daysToKeep created")
    node_num_to_keep = Nokogiri::XML::Node.new('numToKeep', root)
    $log.debug("node logRotator child numToKeep created")
    a_node_days_to_keep = Nokogiri::XML::Node.new('artifactDaysToKeep', root)
    $log.debug("node logRotator child artifactDaysToKeep created")
    a_node_num_to_keep = Nokogiri::XML::Node.new('artifactNumToKeep', root)
    $log.debug("node logRotator child artifactNumToKeep created")
    node['class'] = 'hudson.tasks.LogRotator'
    $log.debug("node keys written")
    node_days_to_keep.content = daystokeep
    node_num_to_keep.content = numtokeep
    a_node_days_to_keep.content = artifactdaystokeep
    a _node_num_to_keep.content = artifactnumtokeep
    $log.debug("child nodes created and populated")
    node.add_child(node_days_to_keep)
    node.add_child(node_num_to_keep)
    node.add_child(a_node_days_to_keep)
    node.add_child(a_node_num_to_keep)
    node.parent = root
    $client.job.update(@job, doc.to_xml)
  end

  def all_discard_on(daystokeep = "-1", numtokeep = "-1", artifactdaystokeep = "-1", artifactnumtokeep = "-1")
    $log.debug("\nEntering Waldo::all_discard_all")
    $client.job.list_all.each { |job| job_discard_on(daystokeep, numtokeep, artifactdaystokeep, artifactnumtokeep) }
  end

  def job_list_all
    # obtain a list of every job on the jenkins server
    $log.debug("\nEntering Waldo::job_list_all")
    $log.info($client.job.list_all)
  end

  def job_search_name
    # use regex to match partial_name and output to user
    $log.debug("\nEntering Waldo::job_search_name")
    to_filter = @job
    filtered_list = $client.job.list("#{to_filter}")
    if filtered_list.nil? || filtered_list == []
      $log.info "Nothing found matching '#{@job}'"
    else
      $log.info(filtered_list)
     end
  rescue Timeout::Error => e
     puts "#{e} waiting on job.list(#{to_filter})"
     retry
  end
 
 ##########################################################################
 # private members past this point
 ########################################################################## 
  
  private

  def config_obtain
    $log.debug("\nentering Waldo::config_obtain")
    Nokogiri::XML.parse($client.job.get_config(@job.to_s))
  end

  def clean_txt(text)
    $log.debug("\nentering Waldo::clean_txt")
    text.to_s.gsub!(/<\/?[[:alpha:]]+>/,'')
  end

  def discard_checkbox?(doc)
    $log.debug("\nentering Waldo::discard_checkbox")
    if doc.to_s.include?('logRotator') && ((
        doc.xpath("//daysToKeep").inner_text.to_i > 0) ||
        (doc.xpath("//numToKeep").inner_text.to_i > 0) ||
        (doc.xpath("//artifactDaysToKeep").inner_text.to_i > 0) ||
        (doc.xpath("//artifactNumToKeep").inner_text.to_i > 0))
      return true
    else
      return false
    end
  end
  
  def parsing_spec(contents)
  # will take the current contents of <spec> and break it down into
  # "active code", "comments", and "backed up"
  # it will then return a hash of arrays of arrays:  activecode =>,
  # comments =>, backedup =>
  #
  # useful for dealing with edge cases, etc - allows rebuilding of a polling
  # spec by individual components
    split_contents = { "activecode" => [], "comments" => [], "backedup" => [] }
    contents.gsub!("#{$CLIJ_MSG_HEADER}\n", '')
    contents.split("\n").map do |line|
      if line.start_with?("### ")
        split_contents["backedup"] << line
      elsif line.start_with?("#")
        split_contents["comments"] << line
      else
        split_contents["activecode"] << line
      end
    end
    return split_contents
  end

  def recoverable_action(job_list)
    $log.debug("\nEntering Waldo::recoverable_action")
    file = File.open("#{@HOMEDIR}/#{@DUMP_FILE}", "w")
    $log.debug(file)
    save_data = Marshal.dump(job_list, file)
    $log.info("Remaining jobs dumped.  Re-run command line to continue from where you left off.")
  end

  def load_dump_file
  # loads a found dump file and returns its contents
  # to the caller
    $log.debug("\nEntering Waldo::load_dump_file")
    $log.debug("Using dump file to restart job")
    file = File.open("#{@HOMEDIR}/#{@DUMP_FILE}", "r")
    list_of_jobs = Marshal.load(file)
    $log.debug("Deleting dump file...")
    File.delete("#{@HOMEDIR}/#{@DUMP_FILE}")
    return list_of_jobs
  end

  def dump_file?
    $log.debug("\nEntering Waldo::dump_file?")
    if File.file?("#{@HOMEDIR}/#{@DUMP_FILE}")
      return true
    else
      return false
    end
  end

end  # class Waldo

