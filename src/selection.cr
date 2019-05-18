class Selection
  getter selected_files = [] of String
  property multiple_selection = false
  def initialize
  end
  # is given file in selected array
  # 2019-04-24 - now takes fullname so path addition does not keep happening in
  #  a loop in draw directory.
  def selected?(fullname)
    return @selected_files.index fullname
  end

  # add given file/s to selected file list
  def add_to_selection(file : Array)
    ff = file
    ff.each do |f|
      full = File.expand_path(f)
      @selected_files.push(full) unless @selected_files.includes?(full)
    end
  end

  def remove_from_selection(file : Array)
    ff = file
    ff.each do |f|
      full = File.expand_path(f)
      @selected_files.delete full
    end
  end

    # unselect all files
    def unselect_all
      @selected_files = [] of String
      # @toggles["visual_mode"] = @visual_mode = false
    end

    # remove non-existent files from select list due to move or delete
    #  or rename or whatever
    def clean_selected_files
      @selected_files.select! { |x| x = File.expand_path(x); File.exists?(x) }
    end
    def toggle_select(f)
      return unless f
      # if selected? File.join(@current_dir, current_file)
      if selected? File.expand_path(f)
        remove_from_selection [f]
      else
        @selected_files.clear unless @multiple_selection
        add_to_selection [f]
      end
    end

end
