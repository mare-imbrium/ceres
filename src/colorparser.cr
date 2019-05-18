class Colorparser
  def initialize
    # NOTE: that osx uses LSCOLORS which only has colors for filetypes not
    #  extensions and patterns which LS_COLORS has.
    # LS_COLORS contains 2 character filetype colors. ex executable mi broken link
    #   extension based colros starting with '*.'
    #   file pattern starting with '*' and a character that is not .
    #   File.ftype(path) returns
    #   file, directory di, characterSpecial cd, blockSpecial bd, fifo pi, link ln, socket so, or unknown

    # This hash contains color codes for extensions. It is updated from
    # LS_COLORS.
    @ls_color = {
      ".rb"      => RED,
      ".tgz"     => MAGENTA,
      ".zip"     => MAGENTA,
      ".torrent" => GREEN,
      ".srt"     => GREEN,
      ".part"    => "\e[40;31;01m",
      ".sh"      => CYAN,
    }
    # This hash contains colors for file patterns, updated from LS_COLORS
    @ls_pattern = {} of String => String
    # This hash contains colors for file types, updated from LS_COLORS
    # Default values in absence of LS_COLORS
    # crystal sends Directory, with initcaps, Symlink, CharacterDevice, BlockDevice
    # Pipe, Socket and Unknown https://crystal-lang.org/api/0.28.0/File/Type.html
    @ls_ftype = {
      "Directory" => BLUE,
      "Symlink"   => "\e[01;36m",
      "mi"        => "\e[01;31;7m",
      "or"        => "\e[40;31;01m",
      "ex"        => "\e[01;32m",
    }
  end
    # determine color for a filename based on extension, then pattern, then filetype
    def color_for(f)
      return nil if f == SEPARATOR

      fname = f.starts_with?("~/") ? File.expand_path(f) : f

      extension = File.extname(fname)
      color = @ls_color[extension]?
      return color if color

      # check file against patterns
      if File.file?(fname)
         @ls_pattern.each do |k, v|
           # if fname.match(/k/)
           if /#{k}/.match(fname)
              # @@log.debug "#{fname} matched #{k}. color is #{v[1..-2]}"
             return v
              # else
              # @@log.debug "#{fname} di not match #{k}. color is #{v[1..-2]}"
           end
         end
      end

      # check filetypes
      if File.exists? fname

        ftype = File.info(fname).type.to_s # it was File::Type thus not matching
        # @@log.debug "Filetype:#{ftype}, #{ftype.class}."
        # CRYSTAL ftype
        return @ls_ftype[ftype]? if @ls_ftype.has_key?(ftype)
        # @@log.debug "went past ftype for #{fname}"
        return @ls_ftype["ex"]? if File.executable?(fname)
      else
        # orphan file, but fff uses mi
        return @ls_ftype["mi"]? if File.symlink?(fname)

        # @@log.warn "FILE WRONG: #{fname}"
        return @ls_ftype["or"]?
      end

      nil
    end

    def parse_ls_colors
      colorvar = ENV["LS_COLORS"]?
      if colorvar.nil?
        @ls_colors_found = nil
        return
      end
      @ls_colors_found = true
      ls = colorvar.split(":")
      ls.each do |e|
        next if e == ""
        patt, colr = e.split "=" # IOOB CRYSTAL, split throws error if blank
        colr = "\e[" + colr + "m"
        if e.starts_with? "*."
          # extension, avoid '*' and use the rest as key
          @ls_color[patt[1..-1]] = colr
          # @@log.debug "COLOR: Writing extension (#{patt})."
        elsif e[0] == '*'
          # file pattern, this would be a glob pattern not regex
          # only for files not directories
          patt = patt.gsub(".", "\.")
          patt = patt.sub("+", "\\\+") # if i put a plus it does not go at all
          patt = patt.gsub("-", "\-")
          patt = patt.tr("?", ".")
          patt = patt.gsub("*", ".*")
          patt = "^#{patt}" if patt[0] != "."
          patt = "#{patt}$" if patt[-1] != "*"
          @ls_pattern[patt] = colr
          # @@log.debug "COLOR: Writing file (#{patt})."
        elsif patt.size == 2
          # file type, needs to be mapped to what ruby will return
          # file, directory di, characterSpecial cd, blockSpecial bd, fifo pi, link ln, socket so, or unknown
          # di = directory
          # fi = file
          # ln = symbolic link
          # pi = fifo file
          # so = socket file
          # bd = block (buffered) special file
          # cd = character (unbuffered) special file
          # or = symbolic link pointing to a non-existent file (orphan)
          # mi = non-existent file pointed to by a symbolic link (visible when you type ls -l)
          # ex = file which is executable (ie. has 'x' set in permissions).
          case patt
          when "di"
            @ls_ftype["Directory"] = colr
          when "cd"
            @ls_ftype["CharacterDevice"] = colr
          when "bd"
            @ls_ftype["BlockDevice"] = colr
          when "pi"
            @ls_ftype["Pipe"] = colr
          when "ln"
            @ls_ftype["Symlink"] = colr
          when "so"
            @ls_ftype["Socket"] = colr
          else
            @ls_ftype[patt] = colr
          end
          # @@log.debug "COLOR: ftype #{patt}"
        end
      end
    end
end # class
