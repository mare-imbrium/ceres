class Directory
  setter long_listing   = false

  def initialize
    @hidden             = false
    @ignore_case        = false
    @sort_func          = :path
    @sort_reverse       = false
    @enhanced_mode      = true
    @group_directories  = :first
    @sorto              = ""
    @rescan_required    = false
    @current_dir        = ""
    @files              = [] of String
  end

  def enhanced_mode(fl=true)
    @enhanced_mode = fl
  end

  def zsh_sort_order(so)
    @sort_func = sort_func(so)
    @sort_reverse = so[0] == "O"
  end

  def hidden(flag=true)
    @hidden = flag
  end

  def ignore_case(flag=true)
    @ignore_case = flag
  end

  def group_directories(fl=:first)
    @group_directories = fl
  end

  # return a list of directory contents sorted as per sort order
  # NOTE: FNM_CASEFOLD does not work with Dir.glob
  # XXX _filter unused.
  def list_files(dir = "*")
    dir += "/*" if File.directory?(dir)
    dir = dir.gsub("//", "/")

    # hidden = @options["show_hidden"] #[:current]

    # sort by time and then reverse so latest first.
    sorted_files = if !@hidden
                     Dir.glob(dir, match_hidden: false) - %w[. ..]
                     # Dir.glob(dir) - %w[. ..]
                   else
                     # by default it does show hidden
                     Dir.glob(dir).reject{|f| f.starts_with?('.')}
                   end


    # add slash to directories
    sorted_files = add_slash sorted_files
    # return sorted_files
    @files = sorted_files
    # calculate_bookmarks_for_dir # we don't want to override those set by others
  end

  def read_directory
    @rescan_required = false

    @filterstr ||= "M" # XXX can we remove from here
    @current_dir = Dir.current
    list_files
    sort_directory

    group_directories_first
    return @files unless @enhanced_mode

    enhance_file_list
    @files = @files.uniq
  end

  def sort_directory
    func = @sort_func
    files = @files
    sorted_files =
      # File.send(func, f)
      case func
      when :path
        files.sort_by { |f| f }
      when :size
        files.sort_by do |f|
          if File.exists?(f)
            File.size(f)
          else
            File.info(f, follow_symlinks: false).size
          end
        end
      when :extname
        files.sort_by do |f|
          File.extname(f)
        end
      else
        files.sort_by do |f|
          if File.exists?(f)
            File.info(f).modification_time
          else
            File.info(f, follow_symlinks: false).modification_time
          end
        end
      end

    sorted_files.sort! { |w1, w2| w1.compare(w2, case_insensitive: true) } if func == :path &&
      @ignore_case

    # zsh gives mtime sort with latest first, ruby gives latest last
    sorted_files.reverse! if @sort_reverse
    # return sorted_files
    @files = sorted_files
  end

  # decide sort method based on second character
  # first char is o or O (reverse)
  # second char is macLn etc (as in zsh glob)
  def sort_func(sorto)
    so = sorto ? sorto[1]? : :path
    func = case so
           when 'm'
             :mtime
           when 'L'
             :size
           when 'n'
             :path
           when 'x'
             :extname
           else
             :path
             # raise "func is nil so is #{so}. #{sorto}"
           end
    return func
  end

  # put directories first, then files
  def group_directories_first
    return if @group_directories == :none

    files = @files || [] of String
    dirs = files.select { |f| File.directory?(f) }
    # earlier I had File? which removed links, esp dead ones
    fi = files.reject { |f| File.directory?(f) }
    @files = if @group_directories == :first
               dirs + fi
             else
               fi + dirs
             end
  end

  # If there's a short file list, take recently mod and accessed folders and
  # put latest files from there and insert it here. I take both since recent
  # mod can be binaries / object files and gems created by a process, and not
  # actually edited files. Recent accessed gives latest source, but in some
  # cases even this can be misleading since running a program accesses
  # include files.
  def enhance_file_list
    return unless @enhanced_mode

    @current_dir = Dir.current if @current_dir.empty?

    begin
      actr = @files.size

      # zshglob: M = MARK_DIRS with slash
      # zshglob: N = NULL_GLOB no error if no result, this is causing space to split
      #  file sometimes for single file.

      # if only one entry and its a dir
      # get its children and maybe the recent mod files a few
      # FIXME: simplify condition into one
      if @files.size == 1
        # its a dir, let give the next level at least
        return unless @files.first[-1] == "/"

        d = @files.first
        # zshglob: 'om' = ordered on modification time
        # f1 = `zsh -c 'print -rl -- #{d}*(omM)'`.split("\n")
        f = get_files_by_mtime(d)

        if f && !f.empty?
          @files.concat f
          # @files.concat get_important_files(d) TODO
        end
        return
      end
      #
      # check if a ruby project dir, although it could be a backup file too,
      # if so , expand lib and maybe bin, put a couple recent files
      # FIXME: gemspec file will be same as current folder
      if @files.index("Gemfile") || !@files.grep(/\.gemspec/).empty?
        # usually the lib dir has only one file and one dir
        flg = false
        # @files.concat get_important_files(@current_dir) TODO
        if @files.index("lib/")
          # get first five entries by modification time
          # f1 = `zsh -c 'print -rl -- lib/*(om[1,5]MN)'`.split("\n")
          f = get_files_by_mtime("lib").try(&.first(5))
          # @@log.warn "f1 #{f1} != #{f} in lib" if f1 != f
          if f && !f.empty?
            insert_into_list("lib/", f)
            flg = true
          end

          # look into lib file for that project
          dd = File.basename(@current_dir)
          if f.index("lib/#{dd}/")
            # f1 = `zsh -c 'print -rl -- lib/#{dd}/*(om[1,5]MN)'`.split("\n")
            f = get_files_by_mtime("lib/#{dd}").try(&.first(5))
            # @@log.warn "2756 f1 #{f1} != #{f} in lib/#{dd}" if f1 != f
            if f && !f.empty?
              insert_into_list("lib/#{dd}/", f)
              flg = true
            end
          end
        end

        # look into bin directory and get first five modified files
        if @files.index("bin/")
          # f1 = `zsh -c 'print -rl -- bin/*(om[1,5]MN)'`.split("\n")
          f = get_files_by_mtime("bin").try(&.first(5))
          # @@log.warn "2768 f1 #{f1} != #{f} in bin/" if f1 != f
          insert_into_list("bin/", f) if f && !f.empty?
          flg = true
        end
        return if flg

        # lib has a dir in it with the gem name

      end
      return if @files.size > 15

      # Get most recently accessed directory
      # # NOTE: first check accessed else modified will change accessed
      # 2019-03-28 - adding NULL_GLOB breaks file name on spaces
      # print -n : don't add newline
      # zzmoda = `zsh -c 'print -rn -- *(/oa[1]MN)'`
      # zzmoda = nil if zzmoda == ''
      moda = get_most_recently_accessed_dir
      # @@log.warn "Error 2663 #{zzmoda} != #{moda}" if zzmoda != moda
      if moda && moda != ""
        # get most recently accessed file in that directory
        # NOTE: adding NULL_GLOB splits files on spaces
        # FIXME: this zsh one gave a dir instead of file.
        # zzmodf = `zsh -c 'print -rl -- #{moda}*(oa[1]M)'`.chomp
        # zzmodf = nil if zzmodf == ''
        modf = get_most_recently_accessed_file moda
        # @@log.warn "Error 2670 (#{zzmodf}) != (#{modf}) gmra in #{moda} #{zzmodf.class}, #{modf.class} : Loc: #{Dir.current}" if zzmodf != modf

        raise "2784: #{modf}" if modf && !File.exists?(modf)

        insert_into_list moda, [modf] if modf && modf != ""

        # get most recently modified file in that directory
        # zzmodm = `zsh -c 'print -rn -- #{moda}*(om[1]M)'`.chomp
        modm = get_most_recently_modified_file moda
        # zzmodm = nil if zzmodm == ''
        # @@log.debug "Error 2678 (gmrmf) #{zzmodm} != #{modm} in #{moda}" if zzmodm != modm
        raise "2792: #{modm}" if modm && !File.exists?(modm)

        insert_into_list moda, [modm] if modm && modm != "" && modm != modf
      end

      # # get most recently modified dir
      # zzmodm = `zsh -c 'print -rn -- *(/om[1]M)'`
      # zzmodm = nil if zzmodm == ''
      modm = get_most_recently_modified_dir
      # @@log.debug "Error 2686 rmd #{zzmodm} != #{modm}" if zzmodm != modm

      if modm != moda
        # get most recently accessed file in that directory
        # modmf = `zsh -c 'print -rn -- #{modm}*(oa[1]M)'`
        modmf = get_most_recently_accessed_file modm
        raise "2806: #{modmf}" if modmf && !File.exists?(modmf)

        insert_into_list modm, [modmf] if modmf

        # get most recently modified file in that directory
        # modmf11 = `zsh -c 'print -rn -- #{modm}*(om[1]M)'`
        modmf1 = get_most_recently_modified_file modm
        raise "2812: #{modmf1}" if modmf1 && !File.exists?(modmf1)

        insert_into_list(modm, [modmf1]) if modmf1 && modmf1 != modmf
      else
        # if both are same then our options get reduced so we need to get something more
        # If you access the latest mod dir, then come back you get only one, since mod and accessed
        # are the same dir, so we need to find the second modified dir
      end
    ensure
      # if any files were added, then add a separator
      bctr = @files.size
      @files.insert actr, SEPARATOR if actr && actr < bctr
    end
  end

  # insert important files to end of @files
  def insert_into_list(_dir, file : Array(String))
    # @files.push(*file)
    # CRYSTAL 2019-04-29 - splat only takes tuple
    file.each do |f|
      @files.push(f)
    end
  end
  def get_most_recently_accessed_dir(dir = ".")
    gmr dir, :directory?, :atime
  end

  def get_most_recently_accessed_file(dir = ".")
    gmr dir, :file?, :atime
  end

  def get_most_recently_modified_file(dir = ".")
    gmr dir, :file?, :mtime
  end

  def get_most_recently_modified_dir(dir = ".")
    file = gmr dir, :directory?, :mtime
  end

  # get most recent file or directory, based on atime or mtime
  # dir is name of directory in which to get files, default is '.'
  # type is :file? or :directory?
  # func can be :mtime or :atime or :ctime or :birthtime
  def gmr(dir : String | Nil, type, func)
    # CRYSTAL hardcoded mtime, but need to make copy for directory?
    # check type here and select accordingly.
    dir ||= "."
    file = case type
           when :directory?
             Dir.glob(dir + "/*")
               .select { |f| File.directory?(f) }
           else # file?
             Dir.glob(dir + "/*")
               .select { |f| File.file?(f) }
           end
    return nil if file.empty?

    file = file.max_by { |f| File.info(f).modification_time }
    file = File.basename(file) + "/" if file && type == :directory?
    return file.gsub("//", "/") if file.empty?

    nil
  end

  # return a list of entries sorted by mtime.
  # A / is added after to directories
  def get_files_by_mtime(dir = "*")
    gfb dir, :mtime
  end

  def get_files_by_atime(dir = ".")
    gfb dir, :atime
  end

  # get files ordered by mtime or atime, returning latest first
  # dir is dir to get files in, default '.'
  # func can be :atime or :mtime or even :size or :ftype
  def gfb(dir, func)
    dir += "/*" if File.directory?(dir)
    dir = dir.gsub("//", "/")

    # sort by time and then reverse so latest first.
    sorted_files = Dir[dir].sort_by do |f|
      if File.exists? f
        # File.send(func, f)
        File.info(f).modification_time
        f
      else
        File.info(f, follow_symlinks: false).modification_time
        # sys_stat( f)
        f
      end
    end.reverse

    # add slash to directories
    sorted_files = add_slash sorted_files
    return sorted_files
  end

  # should we do a read of the dir
  def rescan?
    @rescan_required
  end

  def rescan_required(flag = true)
    @rescan_required = flag
  end
  def add_slash(files)
    return files.map do |f|
      File.directory?(f) ? f + "/" : f
    end
    end
  def format_long_listing(f) : String
    return f unless @long_listing
    # return format("%10s  %s  %s", "-", "----------", f) if f == SEPARATOR
    return "%10s  %s  %s" % ["-", "----------", f] if f == SEPARATOR

    begin
      if File.exists? f
        stat = File.info(f)
      elsif f.starts_with?("~/")
        stat = File.info(File.expand_path(f))
      elsif File.symlink?(f)
        # dead link
        # stat = File.lstat(f)
        # CRYSTAL
        stat = File.info(f, follow_symlinks: false)
      else
        # remove last character and get stat
        last = f[-1]
        # CRYSTAL no chop
        stat = File.info(f[0..-2]) if last == " " || last == "@" || last == "*"
      end

      f = if stat
            "%10s  %s  %s" % [
              stat.size.humanize,
              date_format(stat.modification_time),
              f,
            ]
          else
            f = "%10s  %s  %s" % ["?", "??????????", f]
          end
    rescue e : Exception # was StandardError
      # @@log.warn "WARN::#{e}: FILE:: #{f}"
      f = "%10s  %s  %s" % ["?", "??????????", f]
    end

    return f
  end
  # # code related to long listing of files
  GIGA_SIZE = 1_073_741_824.0
  MEGA_SIZE =     1_048_576.0
  KILO_SIZE =          1024.0

  # Return the file size with a readable style.
  # NOTE format is a kernel method. CRYSTAL
  def readable_file_size(size, precision)
    if size < KILO_SIZE
      "%d B" % size
    elsif size < MEGA_SIZE
      "%.#{precision}f K" % [(size / KILO_SIZE)]
    elsif size < GIGA_SIZE
      "%.#{precision}f M" % [(size / MEGA_SIZE)]
    else
      "%.#{precision}f G" % [(size / GIGA_SIZE)]
    end
  end

  # # format date for file given stat
  def date_format(tim)
    # without to_local it was printing UTC
    tim.to_local.to_s "%Y/%m/%d %H:%M"
  end
end
