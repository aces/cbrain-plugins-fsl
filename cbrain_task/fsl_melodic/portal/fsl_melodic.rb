
#
# CBRAIN Project
#
# Copyright (C) 2008-2012
# The Royal Institution for the Advancement of Learning
# McGill University
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# A subclass of CbrainTask to launch FslBet.
#
# Original author: Tristan Glatard
class CbrainTask::FslMelodic < PortalTask

  Revision_info=CbrainFileRevision[__FILE__] #:nodoc:

  def self.properties #:nodoc:
    { :use_parallelizer => true }
  end

  def self.default_launch_args #:nodoc:
    {
      :output_name => "melodic-output"
    }
  end

  def usage
    "You MUST select:
     * an FSL design file, with extension .fsf or CBRAIN type FSLDesignFile.
     * a CSV file containing pairs of Nifti or MINC file names, separated by commas.
     --- The corresponding files must be registered in CBRAIN and you must have access to them.
     --- The file type (MINC or Nifti) is determined based on the file extension (.mnc, .nii or .nii.gz).
     --- The first file in the pair will be treated as a functional file.
     --- The second file in the pair will be treated as an anatomical file.
    "
  end

  def before_form #:nodoc:

    params   = self.params

    ids    = params[:interface_userfile_ids]

    params[:structural_file_ids] = Array.new
    params[:functional_file_ids] = Array.new

    # Checks input files
    ids.each do |id|
      u = Userfile.find(id) rescue nil
      cb_error "Error: input file #{id} doesn't exist." unless u
      cb_error "Error: '#{u.name}' does not seem to be a single file." unless u.is_a?(SingleFile)
      cb_error "Error: found a #{u.type}. \n #{usage}" unless ( u.is_a?(CSVFile) || u.is_a?(FSLDesignFile) || u.name.end_with?(".csv") || u.name.end_with?(".fsf"))
      if u.is_a?(FSLDesignFile) || u.name.end_with?(".fsf")
        cb_error "Error: you may select only 1 design file. \n #{usage}" unless params[:design_file_id].nil?
        params[:design_file_id] = id
      end
      if u.is_a?(CSVFile) || u.name.end_with?(".csv")
        cb_error "Error: you may select only 1 CSV file. \n #{usage}" unless params[:csv_file_id].nil?
        params[:csv_file_id] = id
      end
    end
    cb_error "Error: design file missing. \n #{usage}" if params[:design_file_id].nil?
    cb_error "Error: CSV file missing. \n #{usage}" if params[:csv_file_id].nil?

    # Parses CSV file
    csv_file  = Userfile.find(params[:csv_file_id])
    csv_file.sync_to_cache unless csv_file.is_locally_synced?

    lines    = csv_file.becomes(CSVFile).create_csv_array("\"",",") # Patch used becomes to pretend to be a CSVFile

    lines.each do |line|
      cb_error "Error: lines in CSV file must contain two elements separated by a comma (wrong format: #{line})." unless line.size == 2
      line.each_with_index do |file_name,index|
        file_name.strip!
        # Checks files in line
        cb_error "Error: file #{file_name} (present in #{csv_file.name}) doesn't look like a Nifti or MINC file (must have a .mnc, .nii or .nii.gz extension)" unless ( file_name.end_with?(".nii") || file_name.end_with?(".nii.gz") || file_name.end_with?(".mnc") )
        file_array = Userfile.where(:name => file_name)
        current_user = User.find(self.user_id)
        file_array = Userfile.find_accessible_by_user(file_array.map { |x| x.id }, current_user) rescue [] # makes sure that files accessible by the user are selected
        cb_error "Error: file #{file_name} (present in #{csv_file.name}) not found!" unless file_array.size > 0
        cb_error "Error: multiple files found for #{file_name} (present in #{csv_file.name})" if file_array.size > 1 # this shouldn't happen.
        # Assigns files
        file_id = file_array.first.id
        if index == 0
          params[:functional_file_ids] << file_id
        else
          params[:structural_file_ids] << file_id
        end
      end
    end

    # Parses design file
    design_file = Userfile.find(params[:design_file_id])
    design_file.sync_to_cache unless design_file.is_locally_synced?
    design_file_content = File.read(design_file.cache_full_path)

    option_values = get_option_values_from_design_file_content(design_file_content)
    options = ["tr","ndelete","filtering_yn","brain_thresh",
               "mc","te","bet_yn","smooth","st","norm_yn",
               "temphp_yn","templp_yn","motionevs","bgimage",
               "reghighres_yn","reghighres_search","reghighres_dof",
               "regstandard_yn","regstandard_search","regstandard_dof",
               "regstandard_nonlinear_yn","regstandard_nonlinear_warpres",
               "regstandard_res","varnorm","dim_yn","dim","thresh_yn",
               "mmthresh","ostats","icaopt","analysis","paradigm_hp",
               "npts","alternateReference_yn","totalVoxels"]
    options.each { |option| params[option.to_sym] = option_values[option] }

    params[:template_files]                = get_template_files

    # initializes parameters that are not in the design file
    params[:tr_auto]   = "1"
    params[:npts_auto] = "1"
    params[:totalvoxels_auto] = "1"

    ""
  end

  def get_option_values_from_design_file_content design_file_content
    options = Hash.new
    design_file_content.each_line do |line|
      line.strip!
      line.downcase!
      next if line.start_with? "#"
      tokens = line.split(" ")
      options[(tokens[1].downcase.split(/[(,)]/))[1]] = tokens[2] if tokens[0] == "set"
    end
    return options
  end

  def after_form #:nodoc:
    params.delete :regstandard_file_id unless params[:alternatereference_yn] == "1"
    output_name = (! params[:output_name].strip.present?) ? output_name : params[:output_name].strip
    ""
  end

  def final_task_list #:nodoc:

    params[:functional_file_ids] = params[:functional_file_ids].values
    params[:structural_file_ids] = params[:structural_file_ids].values

    mytasklist = []
    if params[:icaopt] == "1" # creates 1 task per functional file
      n_tasks    = params[:functional_file_ids].size-1
      (0..n_tasks).each do |i|
        task=self.dup # not .clone, as of Rails 3.1.10
        task.params[:functional_file_ids] = [ params[:functional_file_ids]["#{i}".to_i] ]
        task.params[:structural_file_ids] = [ params[:structural_file_ids]["#{i}".to_i] ]
        set_task_parameters(task)
        mytasklist << task
      end
    else # creates only 1 task
      task=self.dup # not .clone, as of Rails 3.1.10
      set_task_parameters(task)
      mytasklist << task
    end
    return mytasklist
  end

  def set_task_parameters task
    ids = []


    ids = task.params[:functional_file_ids].dup
    ids.concat params[:structural_file_ids]
    ids << task.params[:design_file_id]
    ids << task.params[:regstandard_file_id] if task.params[:regstandard_file_id].present? && task.params[:alternatereference_yn] == "1"

    description_strings = []
    task.params[:functional_file_ids].each do |id|
      description << Userfile.find(id).name+" "
    end

    task.params[:task_file_ids] = ids
    task.description = description_strings.join if task.description.blank?

    task.params.delete :interface_userfile_ids
  end

  def get_template_files
    template_files = []
    current_user = User.find(self.user_id)
    user_tags = current_user.available_tags.select {|t| t.name =~ /TEMPLATE/i}
    user_tags.each do |tag|
      user_files ||= Userfile.find_all_accessible_by_user(current_user)
      template_files.concat user_files.select { |u| u.tag_ids.include? tag.id }
    end
    return template_files.map { |f| [f.name,f.id.to_s]}
  end

  def untouchable_params_attributes #:nodoc:
    { :inputfile_id => true, :output_name => true, :outfile_id => true}
  end

end

