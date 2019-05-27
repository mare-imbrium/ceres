#!/usr/local/bin/crystal
# --------------------------------------------------------------------------- #
#         File: ceres
#  Description: Fast file navigation, a port of cetus(ruby)
#               but with a different indexing mechanism
#       Author: jkepler http://github.com/jkepler/
#         Date: 2019-05-01
#      License: MIT
#  Last update: 2019-05-27 14:43
# --------------------------------------------------------------------------- #
# == NOTES
# String.split does not remove empty fields as ruby does.
# == CHANGELOG
# renamed grows to max_items, gcols and glines to columns and lines
# 2019-05-18 - move selection, menu, colorparser out

#  == TODO

require "file_utils"
require "yaml"
require "pathname"
require "logger"
require "./keyhandler"
require "./screen"
require "./directory"
require "./colorparser"
require "./selection"
require "./colorconstants"


module Cet

  SEPARATOR = "-------"
  VERSION     = "0.1.0"

  # @log = Logger.new(File.expand_path("~/tmp/log.txt"))
  Loggy = Logger.new(io: File.new(File.expand_path("~/tmp/cetlog.txt"), "w"))
  Loggy.level = Logger::DEBUG
  Loggy.info "========== ceres started ================="

  STATUS_COLOR = 4       # status line, can be 2 3 4 5 6
  STATUS_COLOR_RIGHT = 8 # status line right part

  class Ceres

    ## ----------------- CONSTANTS ----------------- ##

    CONFIG_PATH = ENV["XDG_CONFIG_HOME"] || File.join(ENV["HOME"], ".config")
    CONFIG_DIR = File.join(CONFIG_PATH, "ceres")
    CONFIG_FILE = File.join(CONFIG_DIR, "conf.yml")

    # hints or shortcuts to get to files without moving
    IDX = ("a".."y").to_a
    IDX.delete "q"
    IDX.concat ("za".."zz").to_a
    IDX.concat ("Za".."Zz").to_a
    IDX.concat ("ZA".."ZZ").to_a

    PAGER_COMMAND = {
      text:    "most",
      image:   "open",
      zip:     "tar ztvf %% | most",
      sqlite:  "sqlite3 %% .schema | most",
      unknown: "open",
    }

    GMARK     = "*"
    VMARK     = "+"
    CURMARK   = ">"
    MSCROLL   = 10
    SPACE     = " "




    # NOTE: if changing binding to symbol, there are many places where searched
    # as string.  Can we change to symbol so responds_to? works and scrap the
    # comment, or place it elsewhere.

    @bindings = {
      "`"      => "main_menu",
      "="      => "toggle_menu",
      "%"      => "filter_menu",
      "M-s"    => "selection_menu",
      "M-o"    => "order_menu",
      "ENTER"  => "select_current",
      "C-p"    => "page_current",
      "C-e"    => "edit_current",
      "C-o"    => "open_current",
      "C-s"    => "toggle_select",
      "C-r"    => "reduce",
      "C-g"    => "debug_vars",
      "*"      => "toggle_multiple_selection",
      "M-a"    => "select_all",
      "M-A"    => "unselect_all",
      "!"      => "execute",
      ","      => "goto_parent_dir",
      "~"      => "goto_home_dir",
      "-"      => "goto_previous_dir",
      "+"      => "goto_dir", # 2019-03-07 - TODO: change binding
      "."      => "pop_dir",
      ":"      => "subcommand",
      "'"      => "goto_bookmark",
      "\""      => "file_starting_with",
      "/"      => "filter_files_by_pattern",
      "M-p"    => "prev_page",
      "M-n"    => "next_page",
      "PgUp"   => "prev_page",
      "PgDn"   => "next_page",
      "Home"   => "goto_top",
      "End"    => "goto_end",
      "SPACE"  => "next_page:Page Down",
      "M-f"    => "select_from_visited_files",
      "M-d"    => "select_from_used_dirs",
      "M-b"    => "bookmark_menu",
      "M-m"    => "create_bookmark",
      "M-M"    => "view_bookmarks",
      "C-c"    => "escape",
      "ESCAPE" => "escape",
      "TAB"    => "views",
      "C-i"    => "views",
      # '?' => 'dirtree',
      "D" => "delete_file",
      # 'M' => 'file_actions most',
      "M" => "move_instant",
      "q" => "quit_command",
      # "RIGHT"   => "column_next",
      "RIGHT" => "select_current",
      "LEFT"  => "goto_parent_dir",
      "BACKSPACE"  => "goto_parent_dir",
      "]"     => "column_next: goto next column",
      "["     => "column_next 1: goto previous column",
      "C-x"   => "file_actions",
      # 'M--' => 'columns_incdec -1: reduce column width',
      # 'M-+' => 'columns_incdec 1: increase column width',
      # 'L' => 'command_file Page n less: Page current file',
      "C-d"     => "cursor_scroll_dn",
      "C-b"     => "cursor_scroll_up",
      "UP"      => "cursor_up",
      "DOWN"    => "cursor_dn",
      "C-SPACE" => "toggle_visual_mode",
      "@"      => "scripts",
      "#"       => "generators",
      "?"       => "print_help",
      "F1"      => "print_help",
      "F2"      => "child_dirs",
      "F3"      => "dirtree",
      "F4"      => "tree",
      "S-F1"    => "dirtree",
      "S-F2"    => "tree",
    }

    def initialize

      @max_items     = 0
      @screen        = Screen.new
      @max_items     = @screen.max_items
      @columns       = 0
      @columns       = @screen.columns
      @directory     = Directory.new
      @colorparser   = Colorparser.new
      @selection     = Selection.new
      @files = [] of String
      @view = [] of String
      @viewport = [] of String
      @vps = 0

      @hk = ""
      @bookmarks = {} of String => String
      @mode = nil
      # @pagesize = 60
      @gviscols = 3
      @saved_gviscols = 0
      @pagesize = Int32.new(@max_items * @gviscols) # can be a func
      @stact = 0                                  # used when panning a folder to next column
      @editor_mode = false # changed 2018-03-12 - so we start in pager mode
      @visual_block_start = -1
      @dir_position = {} of String => Array(Int32)
      @cursor_movement = nil # cursor movement has happened only, don't repaint
      @old_cursor = -1 # nil  # cursor movement has happened only, don't repaint
      @keys_to_clear = -1   # in how many strokes should message be cleared, set later.
      @current_dir = ""
      ## ---------------------------------------------
      # # FLAGS
      @long_listing = false
      @visual_mode = false
      @enhanced_mode = true
      @multiple_selection = true # single select
      # @group_directories = :first
      # truncate long filenames from :right, :left or :center.
      # @truncate_from = :center
      @filename_status_line = true
      @display_file_stats = true
      @selected_files_fullpath_flag = false
      @selected_files_escaped_flag = false
      # @ignore_case = true
      @highlight_row_flag = true # false
      @debug_flag = false
      @date_func = :mtime # which date to display in long listing.
      @left_should_refresh = false  # pressing LEFT should not go up if true

      # See toggle_value
      # we need to set these on startup
      @toggles = {
        "ignore_case" =>                  true,
        "long_listing" =>                 false,
        "enhanced_mode" =>                true,
        "visual_mode" =>                  false,
        "display_file_stats" =>           true,
        "selected_files_fullpath_flag" => false,
        "selected_files_escaped_flag" =>  false,
        "multiple_selection" =>           true,
        "editor_mode" =>                  false,
        "selection_mode" =>               false, # typing hint adds to selection, does not open
        "debug_flag" =>                   false,
        "filename_status_line" =>         true,
        "inc_search" =>                   true,
        "highlight_row_flag" =>           true,
      }
      # These are flags that have multiple values.
      @options = {
        "truncate_from" =>   :center,
        "group_directories" => :first,
        "show_hidden" =>    :hide
      }
      @option_values = {
        "truncate_from" =>  [:left, :right, :center],
        "group_directories" => [:first, :none, :last],
        "show_hidden" =>  [:hide, :reveal]
        }

      @group_directories = :first
      @truncate_from    = :right
      @hidden           = :hide
      @patt             = nil   # search pattern
      @quitting         = false
      @modified         = false
      @writing          = false

      @visited_files = [] of String
      # # dir stack for popping
      @visited_dirs = [] of String
      # # dirs where some work has been done, for saving and restoring
      @used_dirs = [] of String

      # zsh o = order m = modified time
      @default_sort_order = "Om"
      @sorto = "Om" # current sort order
      @viewctr = 0
      # # sta is where view (viewport) begins, cursor is current row/file
      @sta = 0
      @cursor = 0

      # Menubar on top of screen
      @help = "#{BOLD}?#{BOLD_OFF} Help   #{BOLD}`#{BOLD_OFF} Menu   #{BOLD}!#{BOLD_OFF} Execute   #{BOLD}=#{BOLD_OFF} Toggle   #{BOLD}C-x#{BOLD_OFF} File Actions  #{BOLD}q#{BOLD_OFF} Quit "

    end



    def read_directory

      # set variables before calling ignore_case hidden, enhanced_mode, sort_order
      @directory.hidden( @options["show_hidden"] == :hide )
      @directory.group_directories( @options["group_directories"] )
      @directory.ignore_case( @toggles["ignore_case"] )
      @directory.enhanced_mode( @toggles["enhanced_mode"] )

      @directory.zsh_sort_order(@sorto)
      @files = @directory.read_directory
    end

    def list_files
      @directory.long_listing = @long_listing
      @directory.list_files
      calculate_bookmarks_for_dir # we don't want to override those set by others
    end

    # ------------------- create_viewport ------------------ #
    def create_viewport
      @view = if @patt
                 if @toggles["ignore_case"]
                   @files.grep(/#{@patt}/i)
                 else
                   @files.grep(/#{@patt}/)
                 end
               else
                 @files
               end

      fl = @view.size
      @sta = 0 if @sta >= fl || @sta < 0
      @cursor = 0 if @cursor >= fl || @cursor < 0

      # NOTE if we make cursor zero, then it can be < sta so in the next line
      #  it will be made equal to sta which we may not want
      @cursor = @sta if @sta > @cursor

      # viewport are the files that are visible, subset of view
      @viewport = @view[@sta, @pagesize]
      @vps = @viewport.size
    end

    # FIXME: need to update when bookmark created or deleted
    def calculate_bookmarks_for_dir
      bm = @bookmarks.select { |_k, v| v == @current_dir }.keys.join(",")
      bm = " ('#{bm})" if bm && bm != ""
      @bm = bm
    end

    # ------------------- print_title ------------------ #
    def print_title
      # print help line and version
      print "#{GREEN}#{@help}  #{BLUE}ceres  #{VERSION}#{CLEAR}\n"
      @current_dir = Dir.current if @current_dir.empty?

      # print 1 of n files, sort order, filter etc details
      @title ||= @current_dir.sub(ENV["HOME"], "~")

      # Add bookmark next to name of dir, if exists
      # FIXME This should not happen in other listings like find selected files etc

      fin = @sta + @vps
      fl = @view.size

      # fix count of entries so separator and enhanced entries don't show up
      if @toggles["enhanced_mode"]
        ix = @viewport.index SEPARATOR
        fin = @sta + ix if ix

        ix = @view.index SEPARATOR
        fl = ix if ix
      end

      t = fl.zero? ? "#{@title}#{@bm}  No files." :
        "#{@title}#{@bm}  #{@sta + 1} to #{fin} of #{fl}  #{@sorto} F:#{@filterstr}"

      # don't exceed columns while printing
      t = t[t.size - @columns..-1] if t.size >= @columns

      print "\r#{BOLD}#{t}#{CLEAR}"

      tput_cup(-1, @columns - @hk.size - 2)
      puts "[" + @hk + "]"
      print "\r"

      # if no files, print "empty"
      print "#{CURSOR_COLOR}EMPTY#{CLEAR}" if fl == 0
    end

    # TODO: clean this up and simplify it
    # NOTE: earlier this was called on every key (up-arow down arrow, now only
    # called when page changes, so we only put directory name)
    # NOTE: called only from draw_directory.
    def status_line
      # prompt
      v_mm = @mode ? "[#{@mode}] " : ""
      cf = current_file
      @message = " | No matches. Press ESCAPE " if @patt && !cf

      clear_last_line

      # Print the filename at the right side of the status line
      # sometimes due to search, there is no file
      if cf
        print_filename_status_line if @filename_status_line
      end
      # move to beginning of line, reset text mode after printing
      # patt and message are together, no gap, why not ? 2019-04-08 -
      if @patt && @patt != ""
        patt = if @toggles["ignore_case"]
                 "[/#{@patt}/i]"
               else
                 "[/#{@patt}]" # to get unfrozen string
               end
        # patt[-1] = "/i]" if @ignore_case # CRYSTAL no []=
      end
      # bring cursor to start of line
      # add background color
      # print mode
      # print search pattern if any
      # print message if any
      # print "\r#{v_mm}#{patt}#{@message}\e[m"
      print "\r\e[33;4#{STATUS_COLOR}m#{v_mm}#{patt}#{@message}\e[m"
    end

    # def print_debug_info(cf = current_file)
      # return unless cf
      # @screen.print_on_right "len:#{cf.size}/#{@temp_wid} = {@sta},#{@cursor},#{@stact},#{@vps},#{@max_items} | #{cf}", @status_color_right
    # end

    def print_filename_status_line(cf = current_file)
      return unless cf
      if @display_file_stats
        ff = if cf.starts_with?("~/")
               File.expand_path(cf)
             else
               cf
             end

        mtime = if !File.exists? ff
                  # take care of dead links lstat
                  if File.symlink?(ff)
                    stat = File.info(ff, follow_symlinks: false)
                  # date_format(File.info(ff).mtime) if File.symlink?(ff)
                    @directory.date_format(stat.modification_time) if File.symlink?(ff)
                  else
                    Loggy.debug "FILE: #{ff} not exist 686"
                    "??"
                  end
                else
                  @directory.date_format(File.info(ff).modification_time)
                end
      end
      mtime = "| #{mtime} |" if mtime
      # print size and mtime only if more data requested.
      @screen.print_on_right "#{mtime}  #{cf}".rjust(40), STATUS_COLOR_RIGHT
    end

    # should we do a read of the dir
    def rescan?
      @directory.rescan?
    end

    def rescan_required(flag = true)
      @directory.rescan_required(flag)
      redraw_required if flag
    end

    def redraw(flag = false)
      read_directory if flag

      draw_directory
    end

    def draw_directory
      # view consists of all files (filtered by pattern if necessary)
      # viewport is only that subset of view that is displayed on screen
      create_viewport
      @screen.clear_screen
      print_title

      # break viewport into as many columns as required
      buff = columnate @viewport, @max_items

      # starts printing array on line 3
      # added \r otherwise WINCH does not print lines 2019-05-13 -
      buff.each { |line| print "\r", line, "\n" }
      print ""

      status_line

      # place cursor correctly, we will use this to highlight current row
    end

    # place cursor correctly, we will use this to highlight current row
    # XXX i am not sure how to highlight the bg without rewriting the text.
    # I can get the filename but it has been truncated.
    # I can get the earlier filename but the color has to be determined again.
    # FIXME color of original hint lost if @highlight_row_flag.
    # we can even get the filename, but it has been formatted and could
    # be a long listing.
    # color can be CURSOR_COLOR or CLEAR
    # if CLEAR then we use original colors from get_formatted_filename.
    # Otherwise we need to use CURSOR_COLOR in place of current color
    def place_cursor(color = CURSOR_COLOR)
      # empty directory
      if @vps == 0
        tput_cup 0, 0
        return
      end

      c = @cursor - @sta
      # NOTE: cursor can be higher that viewport !!!
      # we need to move it to next page TODO
      if c > @vps
        c = 0
      end

      wid = get_width @vps, @max_items
      if c < @max_items
        rows = c
        cols = 0
      else
        rows = c % @max_items
        cols = (c / @max_items) * wid
      end

      tput_cup rows, cols
      return unless @highlight_row_flag

      color = nil if color == CLEAR # let it determine its own color
      f = get_formatted_filename(c, wid)

      f = color + f + CLEAR if color

      # f = color + f if color # NOTE: this was causing 2 issues: color bleed onto
      # status line and top line. And the highcolor of some rows would not go away.
      # If REVERSE_OFF is used, then REVERSE_OFF must also be used
      #
      print f
      tput_cup rows, cols # put it back at start
    end

    # place cursor on row and col taking first two rows into account
    def tput_cup(row, col)
      # we add 3: 2 is for the help and directory line. 1 is since tput is 1 based
      print "\e[#{row + 3};#{col + 1}H"
    end

    def redraw_required(flag = true)
      @redraw_required = flag
    end

    # return value determines if screen is redrawn or not.
    def resolve_key(key)
      clear_message

      # hint mode, pick file based on shortcut
      return select_hint(@viewport, key) if key.match(/^[a-pr-zZ]$/)

      if "0123456789".includes?(key)
        resolve_numeric_key(key)
        # 2019-05-21 - allow BACKSPACE to  act like LEFT
      # elsif key == "BACKSPACE"
        # s = @patt
        # if s && s.size > 0
          # s = s[0..-2]
          # @patt = s
        # end
        # @patt = @patt[0..-2] if @patt.nil? && @patt.size != ""
        # @patt = @patt[0..-2] if @patt && @patt.size > 0
        # CRYSTAL wont let me since @patt can be nil !!!
        # @message = @title = @patt = nil if @patt == ""
        # @title = nil unless @patt
      else
        resolve_binding key
      end
      true
    end

    def resolve_binding(key)
      # fetch binding for key
      x = @bindings[key]?

      # remove comment string so only binding is left
      # x, _ = x.split(":") if x # CRYSTAL IIOB

      # split into binding and args
      # x = x.split if x
      if x
        x = x.sub(/:.*/, "") # remove comment
        x = x.split
        redraw_required # trying here so default 2019-04-26 -
        binding = x.shift
        args = x
        Loggy.debug "got binding for #{key}: #{binding}"
        # send(binding, *args) if binding
        # CRYSTAL with procs in the hash
        if key == "q"
          quit_command
        else
          dispatch binding
        end
      else
        # perror "No binding for #{key}"
        Loggy.debug "No binding for #{key} in dispatch()."
      end
    end

    # Dispatch to appropriate method
    # in some cases the menu caller itself has a case statement that handles
    # so we should not throw and error
    def dispatch(binding , report_error = true)

      case binding.to_s
      when "main_menu"
        main_menu
      when "toggle_menu"
        toggle_menu
      when "filter_menu"
        filter_menu
      when "selection_menu"
        selection_menu
      when "view_selected_files"
        view_selected_files
      when "order_menu"
        order_menu
      when "view_menu"
        view_menu
      when "select_current"
        select_current
      when "page_current"
        page_current
      when "edit_current"
        edit_current
      when "open_current"
        open_current
      when "toggle_select"
        toggle_select
      when "reduce"
        reduce
      when "debug_vars"
        debug_vars
      when "toggle_multiple_selection"
        toggle_multiple_selection
      when "toggle_long_listing"
        toggle_long_listing
      when "select_all"
        select_all
      when "unselect_all"
        unselect_all
      when "execute"
        execute
      when "goto_parent_dir"
        goto_parent_dir
      when "goto_home_dir"
        goto_home_dir
      when "goto_previous_dir"
        goto_previous_dir
      when "goto_dir"
        goto_dir
      when "pop_dir"
        pop_dir
      when "subcommand"
        subcommand
      when "goto_bookmark"
        goto_bookmark
      when "file_starting_with"
        file_starting_with
      when "filter_files_by_pattern"
        filter_files_by_pattern
      when "prev_page"
        prev_page
      when "goto_top"
        goto_top
      when "goto_end"
        goto_end
      when "next_page"
        next_page
      when "select_from_visited_files"
        select_from_visited_files
      when "select_from_used_dirs"
        select_from_used_dirs
      when "bookmark_menu"
        bookmark_menu
      when "create_bookmark"
        create_bookmark
      when "view_bookmarks"
        view_bookmarks
      when "escape"
        escape
      when "views"
        views
      when "delete_file"
        delete_file
      when "quit_command"
        quit_command
      when "column_next"
        column_next
      when "column_next 1"
        column_next 1
      when "file_actions"
        file_actions
      when "cursor_scroll_dn"
        cursor_scroll_dn
      when "cursor_scroll_up"
        cursor_scroll_up
      when "cursor_up"
        cursor_up
      when "cursor_dn"
        cursor_dn
      when "toggle_visual_mode"
        toggle_visual_mode
      when "scripts"
        scripts
      when "generators"
        generators
      when "print_help"
        print_help
      when "child_dirs"
        child_dirs
      when "dirtree"
        dirtree
      when "tree"
        tree
      when "create_menu"
        create_menu
      when "extras"
        extras
      when "create_a_dir"
        create_a_dir
      when "create_a_file"
        create_a_file
      when "create_dir_with_selection"
        create_dir_with_selection
      when "toggle_columns"
        toggle_columns
      when "list_selected_files"
        list_selected_files
      when "page_flags"
        page_flags
      when "locate"
        locate
      when "recent_files"
        recent_files
      when "z_interface"
        z_interface
      when "ag"
        ag
      when "ffind"
        ffind
      when "vidir"
        vidir
      else
        # remove once everything is being called
        if report_error
          perror "Add #{binding} in dispatch()"
          Loggy.debug "DISPATCH: No #{binding}, #{binding.class}"
        end
        return false
      end
      return true
    end

    # numbers represent quick bookmarks
    # if bookmark exists, go to else create it.
    def resolve_numeric_key(key)
      d = @bookmarks[key]?
      if d
        change_dir d
        return
      end

      set_bookmark key
      message "Created bookmark #{key}."
    end

    # v2 if search_as_you_type which takes keyboard control
    # This is fairly straightforward and took only a few minutes to get done.
    # return value is not used.
    def search_as_you_type
      # @patt = "" + "" # rubocop suggestion to get unfrozen string
      @patt = ""
      @title = "Search Results (ENTER to return, ESC to cancel)"
      clear_last_line
      print "\r/"
      loop do
        key = get_char
        if key == "ENTER"
          @title = "Search Results (ESCAPE to return)"
          return true
        elsif key == "ESCAPE"
          @mode = @title = nil
          @patt = nil
          status_line
          return false
        elsif key == "BACKSPACE"
          # @patt = @patt[0..-2] if @patt
          # CRYSTAL WONT LET ME since compile is String or Nil
          s = @patt
          s = s[0..-2] if s
          @patt = s

          @message = nil # remove pesky ESCAPE message
        elsif key.match(/^[a-zA-Z0-9\. _]$/)
          # @patt += key if @patt
          s = @patt
          s += key if s
          @patt = s
        else
          resolve_key key
          @mode = @title = nil
          # if directory changes, then patt is nilled causing error above
          return true
        end
        draw_directory
        place_cursor
      end
    end

    def set_bookmark(key, dir = Dir.current)
      @bookmarks[key] = dir
      calculate_numeric_hotkeys
    end

    def calculate_numeric_hotkeys
      @hk = @bookmarks.select { |k, _| k.match(/[0-9]/) }.keys.sort.join("").as(String)
    end

    # # write current dir to a file so we can ccd to it when exiting
    def write_curdir
      f = File.expand_path("~/.fff_d")
      s = Dir.current
      File.open(f, "w") do |f2|
        f2.puts s
      end
      # puts "Written #{s} to #{f}"
    end


    ##
    #
    # print in columns
    # ary - array of data (viewport, not view) with hint and mark, possibly long listing
    # siz  - how many lines should there be in one column
    #
    def columnate(ary, siz)
      buff = [] of String
      return buff if ary.nil? || ary.empty?

      # determine width based on number of files to show
      # if less than sz then 1 col and full width
      #
      wid = get_width ary.size, siz
      # @temp_wid = wid

      # ix refers to the index in the complete file list, wherease we only show
      # 60 at a time
      ix = 0
      loop do
        # # ctr refers to the index in the column
        #  siz is how many items in one column
        ctr = 0
        while ctr < siz
          f = get_formatted_filename(ix, wid)

          # if already a value in that line, append to it
          if buff[ctr]?
            buff[ctr] += f
          else
            # buff[ctr] = f
            buff.push f
          end

          ctr += 1
          ix += 1
          break if ix >= ary.size
        end
        break if ix >= ary.size
      end
      buff
    end

    # shorten the filename to wid
    # unformatted_len is the length without ANSI formatting
    # wid is the exact width every line should restrict itself to.
    # f is filename with hint and space and possible ANSI codes.
    # WARN: check for hint getting swallowed in case of 5 columns
    def truncate_formatted_filename(f, unformatted_len, wid) : String
      excess = unformatted_len - wid

      f = case @truncate_from
          when :right
            # FIXME: 2019-04-23 - do we need the control code at end ??
            f[0..wid - 3] + "$ "
          when :center
            # from central point calculate how much to remove in both directions
            center = unformatted_len / 2
            excess_half = excess / 2
            point = center + excess_half
            point1 = point - excess

            # remove text between point1 and point
            f[0..(point1 - 1)] + "$" + f[point + 2..-1] + " "
          when :left
            # NOTE: we cannot remove the hint
            # for single hints we need to add extra space
            # there could be escape codes of varying length
            sindex = f.index(" ") || 0
            # 4 = 2 for literals, 2 to get ahead of sindex+1
            f[0..sindex + 1] + "<" + f[sindex + 4 + excess..-1] + " "
          end
      return f || ""
    end

    # given index (in viewport) get a formatted, displayable rendition of the filename
    # returns a String with hint, marks, filename (optional details) and color codes
    # truncated to correct width.
    def get_formatted_filename(ix, wid) : String
      f = @viewport[ix]?
        raise "ix is nil #{ix}. #{@vps}, #{Dir.current}, cur #{@cursor}, sta #{@sta}" unless f

      ind = get_shortcut(ix)
      mark = get_mark(f)
      # make visited files bold
      bcolor = BOLD if mark == VMARK
      # Handle separator before enhanced file list.
      # We do lose a shortcut
      ind = cur = mark = "-" if f == SEPARATOR
      prefix = "#{ind}#{mark}#{cur}"

      # fullname = f[0] == '~' ? File.expand_path(f) : f
      color = @colorparser.color_for(f)
      # Loggy.debug "Color is #{color[1..-2]} for #{f}" if color
      color = "#{bcolor}#{color}"

      # @directory.long_listing = @long_listing
      f = @directory.format_long_listing(f) if @long_listing

      # replace unprintable chars with ?
      f = f.gsub(/[^[:print:]]/, "?")

      f = "#{prefix}#{f}"

      unformatted_len = f.size
      if unformatted_len > wid
        # take the excess out from the center on both sides

        f = truncate_formatted_filename(f, unformatted_len, wid)
        f = "#{color}#{f}#{CLEAR}" if color # NOTE clear not added if not color

      elsif unformatted_len < wid
        # f << ' ' * (wid - unformatted_len)
        f = "#{color}#{f}#{CLEAR}" + " " * (wid - unformatted_len)
      end

      return f
    end

    def get_width(arysz, siz) : Int32
      ars = [@pagesize, arysz].min
      d = 0
      return @columns - d if ars <= siz

      tmp = (ars * 1.000 / siz).ceil
      wid = @columns / tmp - d
      wid.to_i
    end

    def get_mark(file)
      return SPACE if selected_files.empty? && @visited_files.empty?

      @current_dir = Dir.current if @current_dir.empty?
      fullname = File.expand_path(file)

      return GMARK if selected?(fullname)
      return VMARK if visited? fullname

      # 2019-04-27 - this boldfaces visited files, but should only be done if color
      #  otherwise it will overflow.
      #  This was nice but it messes with width in multiple columns truncate
      # return "#{BOLD}+" if visited? fullname

      SPACE
    end



    # # select file based on key pressed
    def select_hint(view, key)
      ix = get_index(key, view.size)
      return nil unless ix

      f = view[ix]
      return nil unless f
      return nil if f == SEPARATOR

      @cursor = @sta + ix

      if @mode == "SEL"
        toggle_select f
      elsif @mode == "COM"
        # not being called any longer I think
        run_command [f]
      else
        open_file f
      end
      true
    end

    # # toggle selection state of file
    def toggle_select(f = current_file)
      @selection.multiple_selection = @multiple_selection
      @selection.toggle_select(f)

      # 2019-04-24 - trying to avoid redrawing entire screen.
      # If multiple_selection then current selection is either added or removed,
      #  nothing else changes, so we redraw only if not multi. Also place cursor
      #  i.e. redraw current row if mutliple selection
      if @multiple_selection
        redraw_required false
        place_cursor
      end
      message "#{selected_files.size} files selected.   "
    end

    # allow single or multiple selection with C-s key
    def toggle_multiple_selection
      @multiple_selection = toggle_value "multiple_selection"
    end

    # # open file or directory
    def open_file(f)
      return unless f

      f = File.expand_path(f) if f.starts_with? "~/"
      unless File.exists? f
        # this happens if we use (T) in place of (M)
        # it places a space after normal files and @ and * which borks commands
        last = f[-1]
        f = f[0..-2] if last == " " || last == "@" || last == "*"
      end

      # could be a bookmark with position attached to it
      f, _nextpos = f.split(":") if f.index(":")
      if File.directory? f
        save_dir_pos
        change_dir f # , nextpos
      elsif File.readable? f
        comm = opener_for f
        # '%%' will be substituted with the filename. See zip
        comm = if comm.index("%%")
                 # comm.gsub("%%", Shellwords.escape(f))
                 comm.gsub("%%", shellescape(f))
               else
                 # comm + " #{Shellwords.escape(f)}"
                 comm + " #{shellescape(f)}"
               end
        @screen.clear_screen
        @screen.reset_terminal
        system(comm.to_s)
        @screen.setup_terminal
        # XXX maybe use absolute_path instead of hardcoding
        f = File.expand_path(f)
        @visited_files.insert(0, f)
        push_used_dirs @current_dir
      else
        perror "open_file: (#{f}) not found"
        # could check home dir or CDPATH env variable DO
      end
      redraw_required
    end

    # regardless of mode, view the current file using pager
    def page_current
      command = ENV["MANPAGER"] || ENV["PAGER"] || "less"
      run_on_current command
    end

    # regardless of mode, edit the current file using editor
    def edit_current
      command = ENV["EDITOR"] || ENV["VISUAL"] || "vim"
      f = current_file
      return unless f
      run_on_current command
      @visited_files.insert(0, File.expand_path(f))
    end

    def open_current
      f = current_file
      return unless f
      # opener = /darwin/.match(RUBY_PLATFORM) ? "open" : "xdg-open"
      opener = "open" # CRYSTAL
      run_on_current opener
      @visited_files.insert(0, File.expand_path(f))
    end

    # run given command on current file
    def run_on_current(command)
      f = current_file
      return unless f

      f = File.expand_path(f)
      return unless File.readable?(f)

      # CRYSTAL no Shellwords
      # f = Shellwords.escape(f)
      f = shellescape(f)
      @screen.clear_screen
      @screen.reset_terminal
      comm = "#{command} #{f}"
      system(comm.to_s)
      push_used_dirs
      @screen.setup_terminal
      redraw_required
    end

    # # run system command on given file/s
    #   Accepts external command from user
    #   After putting readline in place of gets, pressing a C-c has a delayed effect.
    #   It goes into exception block after executing other commands and still
    #   does not do the return !
    def run_command(f)
      # CRYSTAL
      # files = Shellwords.join(f)
      files = shelljoin(f)
      count = f.size
      text = if count > 1
               "#{count} files"
             else
               files[0..40]
             end
      begin
        command = @screen.readline "Run a command on #{text}: "
        return unless command
        return if command.empty?

        # command2 = gets().chomp
        command2 = @screen.readline "Second part of command: "
        pause "#{command} #{files} #{command2}"

        @screen.reset_terminal
        system "#{command} #{files} #{command2}"
        @screen.setup_terminal
      rescue ex : Exception # StandardError
        perror "Canceled or failed command, (#{ex}) press a key."
        Loggy.warn "RUNCOMMAND: #{ex}"
        return
      end

      refresh
      push_used_dirs Dir.current
      # should we clear selection also ?
    end

    # # cd to a dir.
    def change_dir(f)
      unless File.directory? f
        perror "#{f} is not a directory, or does not exist."
        return
      end

      # before leaving a dir we save it in the list, as well as the cursor
      # position, so we can restore that position when we return
      @visited_dirs.insert(0, Dir.current)
      save_dir_pos

      f = File.expand_path(f)
      # Dir.chdir f # CRYSTAL
      Dir.cd f
      @current_dir = Dir.current # 2019-04-24 - earlier was in post_cd but too late
      read_directory
      post_cd

      redraw_required
    end

    def goto_previous_dir
      prev_dir = @visited_dirs.first
      return unless prev_dir

      change_dir prev_dir
    end

    def index_of(dir)
      @files.index(dir)
    end

    # # clear sort order and refresh listing, used typically if you are in some view
    #  such as visited dirs or files
    def escape
      @sorto = @default_sort_order
      @viewctr = 0
      @title = nil
      @filterstr = "M"
      @message = nil
      @mode = nil
      visual_block_clear
      refresh
    end

    # # refresh listing after some change like option change, or toggle
    # Should we check selected_files array also for deleted/renamed files
    def refresh
      @patt = nil
      @title = nil
      rescan_required
    end

    # unselect all files
    def unselect_all
      @selection.unselect_all
      @toggles["visual_mode"] = @visual_mode = false
      message "No files selected."
    end

    def select_all
      dir = Dir.current
      f = @view.map { |file| File.join(dir, file) }
      @selection.add_to_selection(f)
      message "#{selected_files.size} files selected."
    end

    # # accept dir to goto and change to that ( can be a file too)
    def goto_dir
      # print "\e[?25h"
      # print_last_line 'Enter path: '
      begin
        # path = gets.chomp
        path = @screen.readline "Enter path to go to: "
        if path.nil? || path == ""
          clear_last_line
          return
        end
        # rescue => ex
      # rescue e : StandardError
      rescue e : Exception # was StandardError
        # Nope, already caught interrupt and sent back nil
        perror "Cancelled cd, press a key"
        return
      ensure
        # print "\e[?25l"
      end
      return unless path
      f = File.expand_path(path)
      unless File.directory? f
        # # check for env variable
        tmp = ENV[path]?
        if tmp.nil? || !File.directory?(tmp)
          # # check for dir in home
          tmp = File.expand_path("~/#{path}")
          f = tmp if File.directory? tmp
        else
          f = tmp
        end
      end

      open_file f
    end

    # # toggle mode to selection or not
    #  In selection, pressed hotkey selects a file without opening, one can keep selecting
    #  (or deselecting).
    #
    def toggle_selection_mode
      if @mode == "SEL"
        unselect_all
        @mode = nil
        message "Selection mode is single.   "
      else
        @mode = "SEL"
        message "Typing a hint selects the file. Typing again will clear   .  "
      end
    end

    # go to parent dir, and maintain cursor on the dir we came out of
    def goto_parent_dir
      # if in search mode, LEFT should open current dir like escape
      # Not nice to put this in here !!!
      if @mode == "SEARCH" || @left_should_refresh
        escape
        return
      end

      # When changing to parent, we need to keep cursor on
      #  parent dir, not first
      curr = File.basename(Dir.current)

      return if curr == "/"

      change_dir ".."

      return if curr == Dir.current

      # get index of child dir in this dir, and set cursor to it.
      index = @files.index(curr + "/")
      pause "WARNING: Could not find #{curr} in this directory." unless index
      # cursor can be outside the viewport. NOTE
      @cursor = index if index
    end

    def goto_home_dir
      change_dir ENV["HOME"]
    end

    # Goes to directory bookmarked with number or char.
    def goto_bookmark(key = nil)
      unless key
        clear_last_line
        print "Enter bookmark char (? to view): "
        key = get_char
      end
      if key == "?"
        view_bookmarks
        return
      end

      d = @bookmarks[key]?
      if d
        change_dir d
      else
        perror "#{key} not a bookmark. "
      end
    end

    # # take regex from user, to run on files on screen, user can filter file names
    def filter_files_by_pattern
      @title = "Search Results: (Press Esc to cancel)"
      @mode = "SEARCH"
      if @toggles["inc_search"]?
        search_as_you_type
      else
        @patt = @screen.readline "/"
      end
    end

    # page/scroll down.
    def next_page
      @sta += @pagesize
      @cursor += @pagesize
      @sta = @cursor if @sta > @cursor
      @stact = 0
      @old_cursor = -1
      redraw_required
    end

    def prev_page
      @sta -= @pagesize
      @cursor -= @pagesize
      @old_cursor = -1
      # FIXME: check cursor sanity and if not changed then no redraw
      redraw_required
    end

    def goto_top
      @sta = @cursor = 0
      @old_cursor = -1
      redraw_required
    end

    # goto end / bottom
    def goto_end
      @cursor = @view.size - 1
      @sta = @view.size - @pagesize
      @old_cursor = -1
      redraw_required
    end

    def print_help
      page_with_tempfile do |file|
        file.puts %(
    #{REVERSE}             HELP                           #{CLEAR}

    Tilde (`) is the main menu key. Many important operations are
    available through it, or through its sub-menus.

    To open a file or dir, press a-z A-Z (shortcut on left of file)
    Ctrl-s to select file under cursor. * for multiple select.
    Ctrl-Space: Enter and exit Visual Selection mode
    Ctrl-x: file actions for selected files, or file under cursor
    1-9: bookmark a dir, and go to it.

    Use left and right arrows to move through directories

    )
        ary = [] of String
        # 2019-03-19 -  if : then show text after colon
        @bindings.each do |k, v|
          vv = v.tr("_", " ")
          vv = vv.split(":")[1].strip if vv.includes?(":")
          ary.push "   #{k.ljust(7)}  =>  #{vv}"
        end
        # FIXME: this works but not properly when long_listing is true.
        # We should avoid using columnate as there are several file related things.
        # next line no longer working.
        # ary = columnate ary, (ary.size / 2) + 1
        ary.each { |line| file.puts line }
        # TODO: 2019-04-26 - add other hashes for other menus here ?
        # but those hashes are not available
      end
    end # print_help

    def page_stat_for_file
      stat = `stat #{current_file}`
      return unless stat

      page_with_tempfile do |file|
        file.puts stat
      end
    end

    # display values of flag and options in pager
    def page_flags
      # XXX once this is changed to an array, then remove 'keys'
      page_with_tempfile do |file|
        file.puts "Values of toggles/flags"
        file.puts "-----------------------"
        @toggles.each do |flag, value|
          # CRYSTAL
          file.puts "#{flag} : #{value}"
        end
        file.puts "-----------------------"
        @options.each do |flag, value|
          file.puts "#{flag} : #{value}"
        end
      end
    end

    def page_with_tempfile
      # file = Tempfile.new("cetus")
      # CRYSTAL
      file = File.tempfile("ceres")
      begin
        yield file
        file.flush
        system "$PAGER #{file.path}"
        @screen.setup_terminal
      rescue e : Exception # was StandardError
        file.close
        file.delete # CRYSTAL
      end
    end

    def debug_vars
      page_with_tempfile do |file|
        file.puts "DEBUG VARIABLES for #{current_file}:"
        file.puts
        file.puts "sta    #{@sta}"
        file.puts "cursor #{@cursor}"
        file.puts "stact  #{@stact}"
        file.puts "viewport.size  #{@vps}"
        file.puts "pagesize       #{@pagesize}"
        file.puts "view.size      #{@view.size}"
        file.puts "max_items          #{@max_items}"
        file.puts "File: #{current_file}"
        file.puts
        file.puts "Opener: #{opener_for(current_file)}"
        file.puts
        file.puts `file "#{current_file}"`
        file.puts
        file.puts `stat   "#{current_file}"`
      end
      redraw_required
    end

    def view_bookmarks
      clear_last_line
      puts "Bookmarks: "
      @bookmarks.each { |k, v| puts "#{k.ljust(7)}  =>  #{v}" }
      puts
      print "Enter bookmark to goto: "
      key = get_char
      goto_bookmark(key)
    end

    # MENU MAIN
    # maybe a list menu - options for date format, size format, age, truncate_from, inode etc
    def main_menu
      h = {
        "a" => :ag,
        "z" => :z_interface,
        # f => :file_actions,
        "b" =>   :bookmark_menu,
        "c" =>   :create_menu,
        "f" =>   :filter_menu,
        "o" =>   :order_menu,
        "s" =>   :selection_menu,
        "t" =>   :toggle_menu,
        "v" =>   :view_menu,
        "`" => :goto_parent_dir,
        "x" =>   :extras,
      }
      menu "Main Menu", h
    end

    # if menu options returns a hash, then treat as another level menu and process
    #  rather than having to create more of these. but these can be called directly too.
    def view_menu
      h = {
        "f" => :select_from_visited_files,
        "d" => :select_from_used_dirs,
        "b" => :view_bookmarks,
        "s" => :list_selected_files,
        "c" => :child_dirs,
        "r" => :recent_files,
        "t" => :tree,
        "e" => :dirtree,
      }
      menu "View Menu", h
    end

    # copy and move here ?
    def selection_menu
      h = {
        "a"   => :select_all,
        "u"   => :unselect_all,
        "s"   => :toggle_select,
        "*" => :toggle_multiple_selection,
        "x"  => :toggle_visual_mode,
        "m"  => :toggle_selection_mode,
        "v"  => :view_selected_files
      }
      menu "Selection Menu", h
    end

    def bookmark_menu
      h = {
        "v" => :view_bookmarks,
        "c" => :create_bookmark,
        "r" => :remove_bookmark,
        "g" => :goto_bookmark,
      }
      menu "Bookmark Menu", h
    end

    # Create a menu using title, and hash of key and binding
    def menu(title, h )
      return [nil, nil] unless h

      clear_last_line
      pbold title.to_s
      # h.each { |k, v| puts " #{k}: #{v}" }
      # 2019-03-09 - trying out using `column` to print in cols
      ary = [] of String

      # 2019-04-07 - check @bindings for shortcut and get key, add global
      #  binding in brackets
      h.each do |k, v|
        # get global binding
        vs = v.to_s
        scut = @bindings.key_for?(vs)
        scut = " (#{scut})" if scut

        # ary << " #{k}: #{v} #{scut}"
        vs = vs.sub("_menu", "...") if vs.ends_with?("_menu")
        vs = vs.tr("_", " ")
        ary << " [#{k}] #{vs} #{scut}"
      end
      x = ary.join("\n")
      # echo column line bombs when x contains a single quote.
      # If i double quote it then it bombs with double quote or backtick
      #  and prints the entire main menu two times.
      x = x.gsub("'", "single quote")
      # x = x.gsub("`", "back-tick")
      puts `echo '#{x}' | column`

      key = get_char
      binding = h[key]?
      # CRYSTAL cannot convert string to symbol
      # binding ||= h[key.to_sym]
      # TODO: 2019-03-21 - menu's do not have comments, they are symbols
      # binding, _ = binding.split(':')
      if binding
        Loggy.debug("BINDING: class= #{binding.class}")
        # 2019-04-18 - true removed, else 'open' binds to ruby open not OS open
        # without true, many methods here don't get triggered
        dispatch(binding) #if binding.is_a?(Symbol) && responds_to?(binding)
        # send(binding) if respond_to?(binding)
      else
        # perror "No binding for #{key} in menu #{title}"
        Loggy.debug "No binding for #{key}:#{key.class} in menu #{title}"
      end
      redraw_required
      [key, binding]
    end

    def toggle_columns
      @gviscols = if @gviscols == 1
                     3
                   else
                     1
                   end
      x = @max_items * @gviscols
      @pagesize = @pagesize == x ? @max_items : x
      message "Visible columns now set to #{@gviscols}"
      rescan_required
    end

    def old_toggle_show_hidden
      @show_hidden = if @show_hidden == "D"
                       ""
                     else
                       "D"
                     end
    end

    def toggle_editor_mode
      toggle_value "editor_mode"
      @default_command = if @editor_mode
                            ENV["EDITOR"]? # earlier nil # 2019-03-10 -
                            # it was nil so we could set a default command
                          else
                            ENV["MANPAGER"]? || ENV["PAGER"]?
                          end
      message "Default command is #{@default_command}"
    end

    def toggle_long_listing
      toggle_value "long_listing"
      @long_listing = @toggles["long_listing"]? || false
      if @long_listing
        @saved_gviscols = @gviscols
        @gviscols = 1
        @pagesize = @max_items
      else
        @gviscols = @saved_gviscols || 3
        x = @max_items * @gviscols
        @pagesize = @pagesize == x ? @max_items : x
      end
      if @stact > 0
        @sta = @stact
        @stact = 0 # in case user was panned 2019-03-20 -
      end
      message "Long listing is #{@long_listing}, date_func is #{@date_func}. visible columns is #{@gviscols}."
      # rescan_required
    end

    # ----------------- flag related functions -----------------------------------#
    # toggles the value of a toggle flag, also setting the variable if defined
    # WARN: be careful of variable being set directly. Replace such vars one by one.
    def toggle_value(flag)
      x = @toggles[flag] = !@toggles[flag]
      @highlight_row_flag = @toggles["highlight_row_flag"]
      @display_file_stats = @toggles["display_file_stats"]
      @filename_status_line = @toggles["filename_status_line"]
      # CRYSTAL check on instance_variable_set
      # if instance_variable_defined? "@#{flag}"
        # instance_variable_set "@#{flag}", x
        # Loggy.debug "instance_variable_set #{flag}, #{x}"
      # end
      message "#{flag} is set to #{x} "
      return x
    end

    # rotates the value of an option that has multiple values
    def rotate_value(symb)
      curr = @options[symb]
      values = @option_values[symb]
      index = values.index(curr) || 0
      index += 1
      index = 0 if index >= values.size
      x = @options[symb] = values[index]
      # CRYSTAL todo or change
      # instance_variable_set "@#{var}", x if var
      message "#{symb} is set to #{x}. "
      return x
    end

    def cset(symb)
      return if symb.nil? || symb == :""

      if @toggles.has_key? symb
        toggle_value symb
      elsif @options.has_key? symb
        rotate_value symb
        # hardcode variables, we don't know which one changed
        @group_directories = @options["group_directories"]
        @truncate_from = @options["truncate_from"]
        @hidden = @options["show_hidden"]
      else
        Loggy.warn "CSET: #{symb} does not exist. Please check code."
        # raise ArgumentError, "CSET: (#{symb}) does not exist. Please check code."
      end
      rescan_required
      return true
    end

    # ----------------- end of flag related functions ----------------------------#

    def order_menu
      # zsh o = order, O = reverse order
      # ruby mtime/atime/ctime come reversed so we have to change o to O
      lo = nil
      h = {
        "m" => :modified,
        # "a" => :accessed,
        "M" => :oldest,
        "s" => :largest,
        "S" => :smallest,
        "n" => :name,
        "N" => :rev_name,
        # d => :dirs,
        # "c" => :inode,
        "x" => :extension,
        "z" => :clear
      }
      _, menu_text = menu "Sort Menu", h
      case menu_text
      when :modified
        lo = "Om"
      when :accessed
        lo = "Oa"
      when :inode
        lo = "Oc"
      when :oldest
        lo = "om"
      when :largest
        lo = "OL"
      when :smallest
        lo = "oL"
      when :name
        lo = "on"
      when :extension
        lo = "ox"
      when :rev_name
        lo = "On"
      when :dirs
        lo = "/"
      when :clear
        lo = ""
      else
        return
      end
      # # This needs to persist and be a part of all listings, put in change_dir.
      @sorto = lo
      message "Sorted on #{menu_text}"
      rescan_required
    end

    # TODO: create a link
    def create_menu
      h = {
        "f" => :create_a_file,
        "d" => :create_a_dir,
        "s" => :create_dir_with_selection,
        "b" => :create_bookmark
      }
      _, menu_text = menu "Create Menu", h
    end

    # This is quite badly placed and named. Maybe these should go elsewhere
    def extras
      h = {
        "1" => :one_column,
        "2" => :multi_column,
        "c" =>   :columns,
        "s" =>   :scripts,
        "g" =>   :generators,
        # "B" =>   :bindkey_ext_command,
        "f" =>   :page_flags,
        "R" =>   :remove_from_list,
        "v" =>   :vidir,
        "r" =>   :config_read,
        "w" =>   :config_write,
      }
      key, menu_text = menu "Extras Menu", h
      case menu_text
      when :one_column
        @pagesize = @max_items
      when :multi_column
        @pagesize = @max_items * @gviscols
      when :columns
        print "How many columns to show: 1-6 [current #{@gviscols}]? "
        key = get_char
        key = key.to_i
        if key > 0 && key < 7
          @gviscols = key.to_i
          @pagesize = @max_items * @gviscols
        end
      end
    end

    def filter_menu
      _hidden = @options["show_hidden"] #[:current]
      hidden = if _hidden == :reveal
                 "D"
               else
                 ""
               end
      h = {
        "d" => :dirs,
        "f" => :files,
        "e" => :emptydirs,
        "0" => :emptyfiles,
        "r" => :recent_files,
        "a" => :reduce_list, # key ??? XXX
        "x" => :extension
      }
      _, menu_text = menu("Filter Menu", h)
      files = nil
      case menu_text
      when :dirs
        @filterstr = "/M"
        # zsh /M MARK_DIRS appends trailing '/' to directories
        files = `zsh -c 'print -rl -- *(#{@sorto}/M)'`.split("\n", remove_empty: true)
        @title = "Filter: directories only"
      when :files
        @filterstr = "."
        # zsh '.' for files, '/' for dirs
        files = `zsh -c 'print -rl -- *(#{@sorto}#{hidden}.)'`.split("\n", remove_empty: true)
        @title = "Filter: files only"
      when :emptydirs
        @filterstr = "/D^F"
        # zsh F = full dirs, ^F empty dirs
        files = `zsh -c 'print -rl -- *(#{@sorto}/D^F)'`.split("\n", remove_empty: true)
        @title = "Filter: empty directories"
      when :emptyfiles
        @filterstr = ".L0"
        # zsh .L size in bytes
        files = `zsh -c 'print -rl -- *(#{@sorto}#{hidden}.L0)'`.split("\n", remove_empty: true)
        @title = "Filter: empty files"
      when :reduce_list
        files = reduce
      when :extension
        files = filter_for_current_extension
      when :recent_files
        # files = recent_files
        @title = "Filter: files by mtime"
        files = @directory.get_files_by_mtime.first(10)
      else
        return
      end
      # String.split is not removing empty element at end due to newline
      files.pop if files && files.last == ""
      if files && files.size > 0
        @files = files
        @stact = 0
        @message = "Filtered on #{menu_text}. Press ESC to return."
        k = @bindings.key_for?("filter_menu")
        @bm = " (" + k  + ") " if k
        @left_should_refresh = true
      else
        perror "Sorry, No files. "
        @title = nil
      end
    end

    def reduce(pattern = nil)
      pattern ||= @screen.readline "Enter a pattern to reduce current list: "
      @title = "Filter: pattern #{pattern}"
      @bm = "(%r)"
      return unless pattern
      @files = @files.select { |f| f.index(pattern) }
    end

    def filter_for_current_extension
      cf = current_file
      return unless cf
      extn = File.extname(cf)
      return unless extn

      @files = @files.select { |f| !File.directory?(f) && extn == File.extname(f) }
    end

    def select_from_used_dirs
      @title = "Used Directories"
      home = File.expand_path "~"
      @files = @used_dirs.uniq.map { |path| path.sub(home.to_s, "~") }
      k = @bindings.key_for?("select_from_used_dirs")
      @bm = " (" + k + ")" if k
      @left_should_refresh = true
      # redraw_required
    end

    def select_from_visited_files
      @title = "Visited Files"
      home = File.expand_path "~"
      @files = @visited_files.uniq.map { |path| path.sub(home.to_s, "~") }
      k = @bindings.key_for?("select_from_visited_files")
      @bm = " (" + k + ")" if k
      @left_should_refresh = true
      # redraw_required
    end

    # # part copied and changed from change_dir since we don't dir going back on top
    #  or we'll be stuck in a cycle
    def pop_dir
      # the first time we pop, we need to put the current on stack
      @visited_dirs.push Dir.current unless @visited_dirs.index(Dir.current)
      # # XXX make sure thre is something to pop
      d = @visited_dirs.delete_at 0
      # # XXX make sure the dir exists, cuold have been deleted. can be an error or crash otherwise
      @visited_dirs.push d
      Dir.cd d
      @current_dir = Dir.current # 2019-04-24 - earlier was in post_cd but too late
      post_cd
      rescan_required
    end

    # after changing directory
    def post_cd
      @title = @patt = @message = nil
      @sta = @cursor = @stact = 0
      @visual_block_start = -1
      screen_settings
      calculate_bookmarks_for_dir

      # goto last position cursor was in this dir
      revert_dir_pos
    end

    # # read dirs and files and bookmarks from file
    def config_read
      f = File.expand_path(CONFIG_FILE)
      return unless File.readable? f

      # read up used directories
      @used_dirs = [] of String
      file = File.expand_path(File.join(CONFIG_DIR, "dirs.txt"))
      @used_dirs = File.read_lines(file) || ["EMPTY"] #if File.exists?(file)

       # read up opened files
      file = File.expand_path(File.join(CONFIG_DIR, "files.txt"))
      @visited_files = File.read_lines(file) if File.exists?(file)

      hash = loadYML(f)
      h = hash.as_h
      h.each do |k,v|
        @bookmarks[k.as_s] = v.as_s
      end
      # @bookmarks = hash.as(Hash(String, String))
      # @bookmarks = hash["BOOKMARKS"].as(Hash(String,String))
      # @bookmarks = hash.as(Hash(String, String))
      # cant cast YAML::Any as ... CRYSTAL
      # @used_dirs = hash["DIRS"].as(YAML::Any)
      # @visited_files = hash["FILES"].as(Array(String))
      # @visited_files = hash["FILES"].as(YAML::Any)
      # @bookmarks = hash["BOOKMARKS"].as(Hash(String, String))
      # @bookmarks = hash["BOOKMARKS"].as(YAML::Any)
      # TODO CRYSTAL. TYPE
      # @used_dirs.concat get_env_paths
    end

    # not yet added TODO
    def get_env_paths
      files = [] of String
      %w[GEM_HOME PYTHONHOME].each do |p|
        d = ENV[p]?
        files.push d if d
      end
      %w[RUBYLIB RUBYPATH GEM_PATH PYTHONPATH].each do |p|
        d = ENV[p]?
        files.concat d.split(":") if d
      end
      files
    end

    # # save dirs and files and bookmarks to a file
    def config_write

      f1 = File.expand_path(CONFIG_FILE)
      # hash = {} of String => String
      hash = @bookmarks
      # hash["DIRS"] = @used_dirs.select { |dir| File.exists? dir }
      # hash["FILES"] = @visited_files.select { |file| File.exists? file }
      # hash["BOOKMARKS"] = @bookmarks # .select {|file| File.exists? file}
      writeYML hash, f1
      @writing = @modified = false
      message "Saved #{f1}"

      # NOTE: I am using two separate files and not the config yml since I could
      # not convert YML Any to these types.

      # Write used dirs to a file for loading in future
      file = File.expand_path(File.join(CONFIG_DIR, "dirs.txt"))
      File.open(file, "w") { |f|
        f.puts(@used_dirs.join("\n"))
      }

      # Write visited files to a file for loading in future
      file = File.expand_path(File.join(CONFIG_DIR, "files.txt"))
      File.open(file, "w") { |f|
        f.puts(@visited_files.join("\n"))
      }
    end

    # {{{ YML
    def loadYML(filename)
      # hash = YAML.safe_load(File.open(filename))
      # hash = {} of String => (Array(String) | Hash(String, String))
      hash = {} of String => String
      hash = YAML.parse(File.read(filename))
      # puts hash["DIRS"]

      # warn hash.keys.size if OPT_DEBUG
      return hash
    end

    def writeYML(obj, filename)
      # File.open(filename, "w") { |f| f.write obj.to_yaml }
      # File.write(filename, obj.to_yaml)
      File.open(filename, "w") { |f| obj.to_yaml(f) } # writes it to the file

      # warn "Written to file #{filename}" if OPT_DEBUG
    end

    # }}}

    # # accept a character to save this dir as a bookmark
    def create_bookmark
      clear_last_line
      print "Enter A-Z, a-z or 0-9 to create a bookmark: "
      # print "\e[?25h" # unhide cursor
      key = get_char
      # print "\e[?25l" # hide cursor
      if /^[0-9A-Za-z]$/.match(key)
        set_bookmark key
        @modified = true
        message "Created bookmark #{key} for #{File.basename(Dir.current)}."
      else
        perror "Bookmark must be alpha character or number."
      end
    end

    def remove_bookmark
      bmlist = @bookmarks.keys.sort.join("")
      clear_last_line
      print "Enter bookmark to delete: #{bmlist}:"
      key = get_char
      if bmlist.index(key)
        @modified = true
        @bookmarks.delete key
        message "Deleted #{key} "
      else
        perror "Bookmark does not exist"
      end
    end

    # allow user to exit using :q :wq :x
    # Was this supposed to be augmented, or just remain limited like this
    # We should be able to do everything in the menus from here. TODO
    def subcommand
      # clear_last_line
      # pbold 'Subcommand:'
      begin
        prompt = %(
    [q]  quit                              [w]   config write              [d] delete
    [x]  update config + quit              [r]   config read               [r] rename
    [wq] write config + quit               [e]   edit file under cursor    [m] move
    [P]  copy PWD to clipboard             [o]   open file under cursor    [c] copy
    [p]  copy filename to clipboard        [h]   help                      [t] toggle flags
    )
        # command = readline 'Enter command: q x wq P p w e r h :'
        command = @screen.readline prompt
        return if command == ""
      rescue e : Exception # was StandardError
        return
      end
      if command == "q"
        quit_command
      elsif command == "wq"
        @quitting = true
        @writing = true
      elsif command == "w"
        config_write
      elsif command == "r"
        config_read
      elsif command == "x"
        @quitting = true
        @writing = true if @modified
      elsif command == "e"
        edit_current
      elsif command == "o"
        open_current
      elsif command == "d"
        delete_file
      elsif command == "c"
        copy_file
      elsif command == "r"
        rename_file
      elsif command == "m"
        move_file
      elsif command == "h" || command == "help" || command == "?"
        print_help
      elsif command == "P"
        # or should be put current file in clip ?
        system "echo $PWD | pbcopy"
        message "Stored PWD in clipboard (using pbcopy)"
      elsif command == "p"
        system "echo #{current_file} | pbcopy"
        message "Stored #{current_file} in clipboard (using pbcopy)"
      elsif command == "t" || command == "toggle"
        toggle_menu
      else
        perror "Don't know about command #{command}. Try :h or :help"
      end
    end

    # 2019-03-08 - 23:46
    # FIXME returns a String not symbol, so some callers can fail
    def fzfmenu(title, h)
      return unless h

      pbold title.to_s
      # XXX using keys not values since toggle hash being used
      values = h.keys.join("\n")
      binding = `echo "#{values}" | fzf --prompt="#{title.to_s} :"`
      if binding
        binding = binding.chomp
        # TODO it could be another method such as the toggle ones
        dispatch(binding, false) #if respond_to?(binding, true)
      end
      binding
    end

    def toggle_menu
      binding = fzfmenu "Toggles", @toggles.merge(@options)
      return if binding.nil? || binding == ""

      # fzf returns a string, not symbol and we can't convert
      menu_text = binding
      # next wont work CRYSTAL. find another way of ignoring
      # return if responds_to?(menu_text, true) # already handled

      # for visual and selection mode
      # check if respond_to? symbol or toggle + symbol then call and return.
      # TODO hardcode call to 3 methods here
      symb = "toggle_#{menu_text}" #.to_sym
      Loggy.debug "trying #{symb}."
      return if dispatch(symb, false)

      # FIX THIS CRYSTAL
      # if respond_to?(symb, true)
        # Loggy.debug "calling #{symb}."
        # dispatch(symb)
        # return
      # end

      cset menu_text
    end

    def quit_command
      # if we are in some mode, like search results then 'q' should come out.
      if @mode
        escape
        return
      end

      if @modified
        last_line
        puts "Press y to save bookmarks before quitting " if @modified
        print "Press n to quit without saving"
        key = get_char
      else
        @quitting = true
      end
      @quitting = true if key == "n"
      @quitting = @writing = true if key == "y"
    end

    def views
      views = %w[/ om oa Om OL oL On on]
      viewlabels = %w[Dirs Newest Accessed Oldest Largest Smallest Reverse Name]
      @sorto = views[@viewctr]
      @title = viewlabels[@viewctr]
      @viewctr += 1
      @viewctr = 0 if @viewctr >= views.size
      hidden = if @hidden == :reveal
                 "D"
               else
                 nil
               end

      @files = `zsh -c 'print -rl -- *(#{@sorto}#{hidden}M)'`.split("\n", remove_empty: true)

      # difference in ruby and crystal split default behavior
      if @files && @files.last == ""
        @files.pop
      end
      message "#{@files.size} entries."
      @left_should_refresh = true

      redraw_required
    end

    def child_dirs
      @title = "Directories in current directory"
      # M is MARK_DIRS option for putting trailing slash after dir
      # @files = `zsh -c 'print -rl -- *(/#{@sorto}#{hidden}M)'`.split("\n")
      @files = dirs
      message "#{@files.size} directories."
    end

    def dirs(dir = "*")
      # files = Dir.glob(dir, File::FNM_DOTMATCH).select { |f| File.directory?(f) } - %w[. ..]
      files = Dir.glob(dir).select { |f| File.directory?(f) } - %w[. ..]
      files = @directory.add_slash files
      files
    end


    def dirtree
      @title = "Child directories recursive"
      # zsh **/ is recursive
      # files1 = `zsh -c 'print -rl -- **/*(/#{@sorto}#{@hidden}M)'`.split("\n")
      @files = Dir["**/"]
      message "#{@files.size} files."
    end

    #
    # Get a full recursive listing of what's in this dir - useful for small projects with more
    # structure than files.
    def tree
      # Caution: use only for small projects, don't use in root.
      @title = "Full Tree"
      # @files = `zsh -c 'print -rl -- **/*(#{@sorto}#{@hidden}M)'`.split("\n")
      @files = Dir["**/*"]
      message "#{@files.size} files."
    end

    # lists recent files in current dir
    # In some cases it shows mostly .git files, we need to prune those
    def recent_files
      # print -rl -- **/*(Dom[1,10])
      @title = "Recent files"
      # zsh D DOT_GLOB, show dot files
      # zsh om order on modification time
      # NOTE: remove blank entry at end which zsh sends here
      @files = `zsh -c 'print -rl -- **/*(Dom[1,15])'`.split("\n", remove_empty: true).reject { |f| f[0] == '.' }
    end

    def select_current
      # # vp is local there, so i can do @vp[0]
      # open_file @view[@sta] if @view[@sta]
      open_file @view[@cursor] if @view[@cursor]?
    end

    # # create a list of dirs in which some action has happened, for saving
    def push_used_dirs(d = Dir.current)
      # @used_dirs.index(d) || @used_dirs.push(d)
      if @used_dirs.empty?
        @used_dirs.push d
        return
      end
      return if @used_dirs[0]? == d

      @used_dirs.delete(d) if @used_dirs.index(d)
      @used_dirs.insert(0, d)
    end

    def pbold(text)
      puts "#{BOLD}#{text}#{BOLD_OFF}"
    end

    # This is supposed to print on the status line
    # but prints on next line.FIXME 2019-03-24 - 00:08
    def perror(text)
      clear_last_line
      puts "\r#{RED}#{text}. Press a key.#{CLEAR}"
      get_char
    end

    def pause(text = " Press a key.")
      last_line
      print text
      get_char
    end

    # # return shortcut/hint for an index (offset in file array)
    # ix is the index of a file in the complete array (view)
    def get_shortcut(index)
      # Case where user has panned to the right columns:
      # Earlier, we showed '<' in left columns, if user has panned right.
      # Now we show unused shortcuts after exhausting them.
      # return '<' if index < @stact
      if index < @stact
        index = @vps - @stact + index
        i = IDX[index]?
        return i if i

        return "["
      end

      # Normal case (user has not panned columns)
      index -= @stact
      i = IDX[index]?
      return i if i

      "->"
    end

    # # returns the integer offset in view (file array based on a-y za-zz and Za - Zz
    # Called when user types a key
    #  should we even ask for a second key if there are not enough rows
    #  What if we want to also trap z with numbers for other purposes
    def get_index(key, vsz = 999)
      # Loggy.debug "Etners get_index with #{key}"
      i = convert_key_to_index key
      return i if i

      if vsz > 25
        if key == "z" || key == "Z"
          last_line
          print key
          zch = get_char
          print zch
          i = convert_key_to_index("#{key}#{zch}")
          # Loggy.debug "convert returned #{i} for #{key}#{zch}"
          return i if i
          # i = IDX.index
          # return i + @stact if i
        end
      end
      nil
    end

    # convert pressed key to an index in viewport.
    # Earlier this was simple, but now that we put hints/shortcuts
    #  in rows on the left after panning, we need to account for cycled hints.
    def convert_key_to_index(key)
      i = IDX.index(key)
      return nil unless i

      # Loggy.debug "get_index with #{key}: #{i}. #{@stact}. #{@vps}"
      # TODO: if very high key given, consider going to last file ?
      #  that way one can press zz or ZZ to go to last file.
      # 2019-04-11 - XXX actually this doesnt place the cursor on last file
      #  it opens it, which may not be what we want
      retnil = nil # vps - 1 # nil
      # user has entered a key that is outside of range, return nil
      return retnil if @stact == 0 && i + @stact >= @vps

      # again, key out of range
      # return nil if @stact > 0 && i + @stact >= @vps && i + @stact - @vps >= @stact
      return retnil if @stact > 0 && i + @stact >= @vps && i - @vps >= 0

      # panning case, hints are recycled
      return (i + @stact) - @vps if i + @stact >= @vps

      # regular hint
      return i + @stact # if i
    end

    def delete_file
      # file_actions :delete
      rbfiles = current_or_selected_files
      return if rbfiles.nil? || rbfiles.empty?

      count = rbfiles.size
      first = rbfiles.first
      text = count == 1 ? File.basename(first) : "#{count} files"
      # shfiles = Shellwords.join(rbfiles)
      shfiles = shelljoin(rbfiles)

      delcommand = "rmtrash"
      clear_last_line
      print "#{delcommand} #{text[0..40]} ? [yn?]: "
      key = get_char
      view_selected_files if key == "?"
      return if key != "y"

      clear_last_line
      print "\r deleting ..."
      ret = system "#{delcommand} #{shfiles}"
      Loggy.info "trashed #{shfiles} ret: #{ret}."
      message "Deleted #{text[0..40]}."
      refresh
    end

    def move_file
      rbfiles = current_or_selected_files
      return if rbfiles.nil? || rbfiles.empty?

      count = rbfiles.size
      first = rbfiles.first
      text = count == 1 ? File.basename(first) : "#{count} files"

      # multiple files can only be moved to a directory
      default = "." #@move_target.nil? ? "." : @move_target
      target = @screen.readline "Move #{text[0..40]} to (#{default}): "
      return unless target

      target = default if target == ""
      target = File.expand_path(target)
      return if target == ""

      if count > 1 && !File.directory?(target)
        perror "Move target must be a directory for multiple files."
        return
      end

      if count == 1 && !File.directory?(target) && File.exists?(target)
        perror "Target #{target} exists."
        return
      end

      begin
        FileUtils.mv rbfiles, target
        message "Moved #{text} to #{target}."
      rescue e : Exception # was StandardError
        Loggy.warn "move_file: #{e}."
        Loggy.warn "MOVE: files: #{rbfiles}, target:#{target}"
        perror e.to_s
      end
      refresh
    end

    def copy_file
      rbfiles = current_or_selected_files
      return if rbfiles.nil? || rbfiles.empty?

      count = rbfiles.size
      first = rbfiles.first
      text = "#{count} files"

      # Target must be directory for multiple files.
      # NOTE: target should not be same as source dir but there can be files
      #  from multiple directories
      if count == 1
        if File.exists? File.basename(first)
          default = get_unique_file_name File.basename(first)
          # CRYSTAL not available
          # Readline::HISTORY.push default
        else
          default = "."
        end
        # default : if file exists here, then add suffix
        # if no file here, then directory is default.
      else
        default = if File.exists? File.basename(first)
                    ""
                  else
                    "."
                  end
        # current directory is default if first file does not exist
        # if first file exists here, then no default
      end
      target = @screen.readline "Copy to (#{default}): "
      return unless target # C-c

      target = default if target == ""
      target = File.expand_path(target)
      return if target == ""

      if count > 1 && !File.directory?(target)
        perror "Copy target must be a directory for multiple files."
        return
      end

      if count == 1 && !File.directory?(target) && File.exists?(target)
        perror "Target #{target} exists."
        return
      end

      # if rbfiles is array, then dest must be a directory.
      # WHY THIS ??#
      # rbfiles = rbfiles.first if rbfiles.size == 1

      begin
        rbfiles.each do |file|
          # cp_r gives error about creating directory
          if File.directory?(file) && File.exists?(target)
            target = File.join(target, File.basename(file))
          end
          FileUtils.cp_r file, target
        end
        message "Copied #{text} to #{target}."
        unselect_all
      rescue e : Exception # was StandardError
        Loggy.warn e.to_s
        Loggy.warn "Target: #{target}, files:#{rbfiles}"
        perror e.to_s
      end
      refresh
    end

    # generate a unique filename by adding a zero padded number prior to the extension.
    # This is used only during copy operation.
    def get_unique_file_name(fname)
      100.times do |i|
        # suffix = format("%03d", i)
        suffix = "%03d" % i
        extn = File.extname(fname)
        base = File.basename(fname, extn)
        # f = fname + '.' + suffix
        f = base + suffix + extn
        return f unless File.exists?(f)
      end

      timestamp = Time.now.to_s("%Y%m%d-%H%M%S")
      return fname + "." + timestamp
    end

    def rename_file
      rbfiles = current_or_selected_files
      return if rbfiles.nil? || rbfiles.empty?

      count = rbfiles.size
      first = rbfiles.first
      text = count == 1 ? File.basename(first) : "#{count} files"

      if count > 1
        perror "Select only one file for rename."
        return
      end

      # Readline::HISTORY.push File.basename(first)
      target = @screen.readline "Rename #{text[0..40]} to : "
      return unless target
      return if target == "" || target == "." || target == ".."

      if File.exists? target
        perror "Target (#{target}) exists."
        return
      end

      begin
        FileUtils.mv first, target
        message "Renamed to #{target}."
        Loggy.info "Renamed #{first} to #{target}."
      rescue e : Exception # was StandardError
        Loggy.warn e.to_s
        Loggy.warn "RENAME: files: #{first}, target:#{target}"
        pause e.to_s
      end
      refresh
    end

    # remove spaces and brackets from file name
    # replace space with underscore, removes square and round brackets
    def remove_spaces_from_name
      execute_script "remove_brackets"
    end

    def shelljoin(array : Array) : String
      array.map { |arg| shellescape(arg) }.join(" ")
    end

    # str can be string or Pathname
    def shellescape(str) : String
      str = str.to_s # for pathname
      str = str.gsub(/([^A-Za-z0-9_\-.,:\/@\n])/, "\\\\\\1")
      str = str.gsub(/\n/, "'\n'")
      return str
      # return file.gsub(" ", "\\\ ").gsub("'", "\\\'")
    end

    def zip_file
      rbfiles = current_or_selected_files
      return if rbfiles.nil? || rbfiles.empty?

      # count = rbfiles.size
      # first = rbfiles.first
      # text = count == 1 ? File.basename(first) : "#{count} files"

      extn = ".tgz"
      default = "archive#{extn}"
      # Readline::HISTORY.push default # check for exist before pushing
      target = @screen.readline "Archive name (#{default}): "
      return unless target
      # CRYSTAL doesnt have push
      # return if target == ""
      target = default if target == ""

      if target && target.size < 4
        perror "Use target of more than 4 characters."
        return
      end
      target += extn if File.extname(target) == ""

      if File.exists? target
        perror "Target (#{target}) exists."
        return
      end

      # convert absolute paths to relative ones in this zip
      # the problem with zip is that we have full paths
      # so the zip file has full paths and extraction sucks
      base = Pathname.new Dir.current
      relfiles = rbfiles.map { |f| p = Pathname.new(f); p.relative_path_from(base) }
 # CRYSTAL
      # zfiles = Shellwords.join relfiles
      zfiles = shelljoin(relfiles)

      system "tar zcvf #{target} #{zfiles}"
      message "Created #{target} with #{relfiles.size} files."
      @screen.setup_terminal
      refresh
    end

    # # generic external command program
    #  prompt is the user friendly text of command such as list for ls, or extract for dtrx, page for less
    #  pauseyn is whether to pause after command as in file or ls
    #
    def command_file(prompt, *command)
      pauseyn = command.shift
      command = command.join " "
      clear_last_line
      print "[#{prompt}] Choose a file [#{@view[@cursor]}]: "
      file = ask_hint @view[@cursor]?
      # print "#{prompt} :: Enter file shortcut: "
      # file = ask_hint
      perror "Command Cancelled" unless file
      return unless file

      file = File.expand_path(file)
      if File.exists? file
        # CRYSTAL
        # file = Shellwords.escape(file)
        file = shellescape(file)
        pbold "#{command} #{file} (#{pauseyn})"
        system "#{command} #{file}"
        @screen.setup_terminal
        pause if pauseyn == "y"
        refresh
      else
        perror "File #{file} not found"
      end
    end

    # # prompt user for file shortcut and return file or nil
    #
    def ask_hint(deflt = nil)
      f = nil
      key = get_char
      return deflt if key == "ENTER"

      ix = get_index(key, @vps)
      f = @viewport[ix] if ix
      f
    end

    # # check screen size and accordingly adjust some variables
    # NOTE: tput is ncurses dependent, so use stty
    #
    def screen_settings
      @screen.get_term_size
      @max_items        = @screen.max_items
      @columns          = @screen.columns
      @pagesize         = @max_items * @gviscols
    end

    # # Tabs to next column in multi-column displays.
    #  Moves column offset so we can reach unindexed columns or entries,
    #  or those with double letters
    # 0 forward and any other back/prev
    # direction is 0 (forward) or '1' (backward)
    def column_next(direction = 0)
      # right movement or panning cycles back to first column
      # leftward movement stops at first column.
      if direction == 0
        @stact += @max_items
        @stact = 0 if @stact >= @vps
        @cursor += @max_items
        # 2019-03-18 - zero loses offset. we need to maintain it
        # @cursor = 0 if @cursor >= @vps
        if @cursor - @sta >= @vps
          while @cursor > @sta
            @cursor -= @max_items
          end
          while @stact > 0
            @stact -= @max_items
          end
          @cursor += @max_items if @cursor < @sta
          @stact += @max_items if @stact < 0
        end
      else
        @stact -= @max_items
        @cursor -= @max_items
        @stact = 0 if @stact < 0
        # setting cursor as zero loses the position or offset
        # We are trying to maintain offset
        @cursor += @max_items if @cursor < 0
      end
    end

    # currently i am only passing the action in from the list there as a key
    # I should be able to pass in new actions that are external commands
    # 2019-03-08 - TODO when a file name changes or moves it must be removed
    #  from selection
    def file_actions(action = nil)
      h = {
        "d" => :delete,
        "D" => "/bin/rm",
        "m" => :move,
        "c" => :copy,
        "r" => :rename,
        "e" => :execute,
        "v" => ENV["EDITOR"] || :vim,
        "o" => :open_current,
        "p" => :most
      }

      rbfiles = current_or_selected_files # use with ruby FileUtils
      return if rbfiles.nil? || rbfiles.empty?

      count = rbfiles.size
      first = rbfiles.first

      h.delete(:r) if count > 1

      if count == 1
        # add chdir if dir of file under cursor is not same as current dir
        h["C"] = :chdir if File.dirname(File.expand_path(first)) != Dir.current

        h["s"] = :page_stat_for_file
        h["f"] = :file
        if filetype(first) == :zip
          h["x"] = :dtrx
          h["u"] = :unzip
        end
        h["g"] = if File.extname(first) == ".gz"
                  :gunzip
                else
                  :gzip
                end
      end
      # h["M"] = :set_move_target if File.directory?(current_file)
      h["z"] = :zip unless filetype(first) == :zip
      h["/"] = :ffind
      h["l"] = :locate

      # if first file has spaces then add remspace method
      # TODO: put this in scripts
      # take care that directories can have spaces
      h["W"] = :remspace if File.basename(first).index " "

      text = count == 1 ? File.basename(first) : "#{count} files"
      # shfiles = Shellwords.join(rbfiles)
      shfiles = shelljoin(rbfiles)

      # --------------------------------------------------------------
      # Use 'text' for display
      # Use 'shfiles' for system actions, these are escaped
      # Use 'rbfiles' for looping and ruby FileUtils, system commands can bork on unescaped names
      # Use 'count' for how many files, in case of single file operation.
      # --------------------------------------------------------------

      # if no action passed, then ask for action
      if action
        menu_text = action
      else
        key, menu_text = menu "File Menu for #{text[0..@columns - 20]}", h
        menu_text = :quit if key == "q"
      end
      return unless menu_text # pressed some wrong key

      case menu_text #.to_sym
      when :quit
        1
      when :delete
        delete_file
      when :move
        move_file
      when :copy
        copy_file
      when :zip
        zip_file
      when :rename
        rename_file
      when :chdir
        change_dir File.dirname(File.expand_path(rbfiles.first)) if count == 1
      when :most, :less, :vim
        system "#{menu_text} #{shfiles}"
        @screen.setup_terminal
        # should we remove from selection ?

      when :remspace
        remove_spaces_from_name
      when :execute
        execute
      when :page_stat_for_file
        1
        # already been executed by menu
        # We could have just put 'stat' in the menu but that doesn't look so nice
      when :locate, :ffind
        1
      else
        return unless menu_text

        clear_last_line
        pause "#{menu_text} #{shfiles} "
        system "#{menu_text} #{shfiles}"
        pause # putting this back 2019-04-13 - file doesn't show anything
        message "Ran #{menu_text}."
        Loggy.info "#{menu_text} #{shfiles}"
        @screen.setup_terminal
        refresh
      end

      return if count == 0

      @selection.clean_selected_files
      visual_block_clear # 2019-04-15 - get out of mode after operation over.
    end

    # increase or decrease column
    def columns_incdec(howmany)
      @gviscols += howmany.to_i
      @gviscols = 1 if @gviscols < 1
      @gviscols = 6 if @gviscols > 6
      @pagesize = @max_items * @gviscols
    end

    # execute a command on selected or current file
    def execute
      run_command current_or_selected_files
    end

    def ag
      pattern = @screen.readline "Enter a pattern to search (ag): "
      return if pattern == ""

      @title = "Files found using 'ag -t: ' #{pattern}"

      # # ag options :
      #     -t : all text files
      #     -l : print only file names
      #     -a : print all files, even ignored
      system %(ag -t "#{pattern}" | less)

      # pause
      files = `ag -lt "#{pattern}"`.split("\n", remove_empty: true)
      if files.empty?
        perror "No files found for #{pattern}."
        @title = nil
        return
      end
      @left_should_refresh = true
      @files = files
    end

    def ffind
      last_line
      # print 'Enter a file name pattern to find: '
      pattern = @screen.readline "! find . -iname :"
      return if pattern == ""

      @title = "Files found using 'find' #{pattern}"
      files = `find . -iname "#{pattern}"`.split("\n", remove_empty: true)
      if files.empty?
        perror "No files found. Try adding *"
      else
        @left_should_refresh = true
        @files = files
      end
    end

    def locate
      # @locate_command ||= /darwin/.match(RUBY_PLATFORM) ? "mdfind -name" : "locate"
      os = `uname`
      @locate_command = if os =~ /Darwin/
                          "mdfind -name"
                        else
                          "locate"
                        end
      pattern = @screen.readline "Enter a file name pattern to #{@locate_command}: "
      return if pattern == ""

      @title = "Files found using: (#{@locate_command} #{pattern})"
      files = `#{@locate_command} #{pattern}`.split("\n", remove_empty: true)
      files.select! { |x| x = File.expand_path(x); File.exists?(x) }
      if files.empty?
        perror "No files found."
        return
      end
      @files = files
      message "#{@files.size} files."
      @mode = "SEARCH"
      @bm = nil
    end

    # #  takes directories from the z program, if you use autojump you can
    #   modify this accordingly
    #
    def z_interface
      file = File.expand_path("~/.z")
      return unless File.exists? file

      @title = "Directories from ~/.z"
      @files = `sort -rn -k2 -t '|' ~/.z | cut -f1 -d '|'`.split("\n", remove_empty: true)
      home = ENV["HOME"]
      # shorten file names
      @left_should_refresh = true
      @files.map! do |f|
        f.sub(/#{home}/, "~")
      end
    end

    def vidir
      system "vidir"
      refresh
      @screen.setup_terminal
    end

    # ------------- movement related methods --------------------------------#

    # # scroll cursor down
    def cursor_scroll_dn
      @cursor_movement = :down
      @old_cursor = @cursor
      move_to(pos + MSCROLL)
    end

    def cursor_scroll_up
      @cursor_movement = :up
      @old_cursor = @cursor
      move_to(pos - MSCROLL)
    end

    # move cursor down a line
    def cursor_dn
      @cursor_movement = :down
      @old_cursor = @cursor
      move_to(pos + 1)
    end

    def cursor_up
      @old_cursor = @cursor
      @cursor_movement = :up
      move_to(pos - 1)
    end

    # return cursor position
    def pos
      @cursor
    end

    # move cursor to given position/line
    def move_to(position)
      orig = @cursor
      place_cursor(CLEAR) if @highlight_row_flag
      @cursor = position
      @cursor = [@cursor, @view.size - 1].min
      @cursor = [@cursor, 0].max

      # try to stop it from landing on separator
      if current_file == SEPARATOR
        @cursor += 1 if @cursor_movement == :down
        @cursor -= 1 if @cursor_movement == :up
        return
      end

      # 2019-03-18 - adding sta
      # @sta = position - only when page flips and file not visible
      # FIXME not correct, it must stop at end or correctly cycle
      # sta goes to 0 but cursor remains at 70
      # viewport.size may be wrong here, maybe should be pagesize only
      oldsta = @sta
      if @cursor - @sta >= @pagesize
        @sta += @pagesize
        # elsif @sta - @cursor >= @vps
      end
      if @sta > @cursor
        @sta -= @pagesize
        # @sta = @cursor
      end

      @cursor_movement = nil if oldsta != @sta # we need to redraw

      # -------- return here --- only visual mode continues ---------------------#
      return unless @visual_mode

      star = [orig, @cursor].min
      fin = [orig, @cursor].max
      @cursor_movement = nil # visual mode needs to redraw page

      # PWD has to be there in selction
      # FIXME with visited_files
      if selected? File.join(@current_dir, current_file)
        # this depends on the direction
        remove_from_selection @view[star..fin]
        # # current row remains in selection always.
        add_to_selection [current_file]
      else
        add_to_selection @view[star..fin]
      end
      message "#{selected_files.size} files selected.   "
    end

    # --

    # is given file in selected array
    def visited?(fullname)
      return @visited_files.index fullname
    end

    # ------------- selection related methods --------------------------------#

    # is given file in selected array
    # 2019-04-24 - now takes fullname so path addition does not keep happening in
    #  a loop in draw directory.
    def selected?(fullname)
      @selection.selected? fullname
    end

    # add given file/s to selected file list
    def add_to_selection(file : Array)
      @selection.add_to_selection file
    end

    def remove_from_selection(file : Array)
      @selection.remove_from_selection file
    end

    # ------------- visual mode methods --------------------------------#
    def toggle_visual_mode
      @mode = nil
      # @visual_mode = !@visual_mode
      toggle_value "visual_mode"
      @visual_mode = @toggles["visual_mode"]
      return unless @visual_mode

      @mode = "VIS"
      @visual_block_start = @cursor
      add_to_selection [current_file]
    end

    # Called from Escape key and scripts and file actions. Clears selection.
    def visual_block_clear
      if @visual_block_start > -1
        star = [@visual_block_start, @cursor].min
        fin = [@visual_block_start, @cursor].max
        remove_from_selection @view[star..fin]
      end
      @visual_block_start = -1
      @toggles["visual_mode"] = @visual_mode = false
      @mode = nil if @mode == "VIS"
      # is this the right place to put this ??? 2019-04-16 -
      @selection.clean_selected_files
    end

    # ------------- file matching methods --------------------------------#
    def file_starting_with(first_char = nil)
      unless first_char
        clear_last_line
        print "\rEnter first char: "
        first_char = get_char
      end
      # ix = return_next_match(method(:file_matching?), "^#{first_char}")
      # CRYSTAL no method
      ix = 0
      goto_line ix if ix
    end

    def file_matching?(file, patt)
      file =~ /#{patt}/
    end

    # # generic method to take cursor to next position for a given condition
    def return_next_match(binding, *args)
      first = nil
      ix = 0
      @view.each_with_index do |elem, ii|
        next unless binding.call(elem, *args)

        first ||= ii
        if ii > @cursor
          ix = ii
          break
        end
      end
      return first if ix == 0

      ix
    end

    ##
    # position cursor on a specific line which could be on a nother page
    # therefore calculate the correct start offset of the display also.
    def goto_line(pos)
      pages = ((pos * 1.00) / @pagesize).ceil
      pages -= 1
      @sta = (pages * @pagesize).to_i + 1
      @cursor = pos
    end

    # return filetype of file using `file` external command.
    # NOTE: Should we send back executable as separate type or allow
    #  it to be nil, so it will be paged.
    def filetype(f)
      return nil unless f

      # f = Shellwords.escape(f)
      # CRYSTAL FIXME TODO
      f = shellescape(f)
      s = `file #{f}`
      return :text if s.index "text"
      return :zip if s.index(/[Zz]ip/)
      return :zip if s.index("archive")
      return :image if s.index "image"
      return :sqlite if s.index "SQLite"
      # return :db if s.index 'database'
      return :text if s.index "data"

      nil
    end

    def opener_for(f) : String
      return "less" if f.nil?
      # by default, default command is nil. Changed in toggle_pager_mode
      @default_command ||= "$PAGER"
      # by default mode, is false, changed in toggle_pager_mode
      # Get filetype, and check for command for type, else extn else unknown
      if !@editor_mode
        ft = filetype f
        # Loggy.debug "opener: #{ft} for #{f}"
        comm = PAGER_COMMAND[ft] if ft
        comm ||= PAGER_COMMAND[File.extname(f)]?
        comm ||= PAGER_COMMAND[:unknown]?
        # Loggy.debug "opener: #{comm}"
      else
        # 2019-04-10 - what does this mean, that in editor_mode, editor
        # opens everything? what of images etc
        # TODO use editor only for text, otherwise use filetype or another hash
        # like editor_command
        comm = @default_command
      end
      comm ||= @default_command
      comm ||= "less"
    end

    # save offset in directory so we can revert to it when we return
    def save_dir_pos
      # the next line meant that it would not save first directory.
      # return if @sta == 0 && @cursor == 0

      @dir_position[Dir.current] = [@sta, @cursor]
    end

    # revert to the position we were at in this directory
    def revert_dir_pos
      @sta = 0
      @cursor = 0
      a = @dir_position[Dir.current]?
      if a
        @sta = a.first
        @cursor = a[1]
        raise "sta is nil for #{Dir.current} : #{@dir_position[Dir.current]}" unless @sta
        raise "cursor is nil" unless @cursor
      end
    end

    def create_a_dir
      str = @screen.readline "Enter directory name: "
      return unless str
      return if str == ""

      if File.exists? str
        perror "#{str} exists."
        return
      end
      begin
        FileUtils.mkdir str
        @used_dirs.insert(0, str) if File.exists?(str)
        refresh
      rescue e : Exception # was StandardError
        perror "Error in newdir: #{e}"
      end
    end

    def create_a_file
      str = @screen.readline "Enter file name: "
      return if str.nil? || str == ""

      system %($EDITOR "#{str}")
      @screen.setup_terminal
      @visited_files.insert(0, File.expand_path(str)) if File.exists?(str)
      refresh
    end

    # convenience method to return file under cursor
    # can return nil if no file in directory
    def current_file : String
      @view[@cursor]? || "." # trying this otherwise catching errors everywhere
    end

    def current_or_selected_files
      return selected_files unless selected_files.empty?

      return [current_file]
    end

    # ------------------- scripts ------------------ #
    # prompt for scripts to execute, giving file name under cursor
    def scripts(binding = nil)
      # some scripts may work with the selected_files and not want to be called
      #  with filenames.
      write_selected_files

      unless binding
        title = "Select a script"
        script_path = File.join(CONFIG_PATH, "ceres", "scripts")
        binding = `find #{script_path} -type f | fzf --prompt="#{title} :"`.chomp
        return if binding.nil? || binding == ""
      end
      unless File.exists? binding
        Loggy.warn "Unable to find #{binding}"
        return
      end

      # TODO: check if binding is a file and executable
      # xargs only seems to take the first file
      # cf = current_or_selected_files.join('\0')
      # cf = Shellwords.join(current_or_selected_files)
      # This was getting called repeatedly even if script used selected_files
      # current_or_selected_files.each do |file|
      # system %( #{binding} "#{file}" )
      # end

      # 2019-04-08 - to avoid confusion, we pass name of file under cursor
      # script may ignore this and use selected_files

      # reset clears the screen, we don't want that. just unhide cursor and echo keys TODO
      @screen.partial_reset_terminal
      Loggy.info "Calling #{binding}."
      system %( #{binding} "#{current_file}" )

      # system %(echo "#{cf}" | xargs #{binding})
      pause
      @screen.setup_terminal
      visual_block_clear
      refresh
    end

    # this is quite important and should not be left to a script
    # example of calling a script from somewhere directly without selection
    def execute_script(filename)
      # script_path = '~/.config/cetus/scripts'
      script_path = File.join(CONFIG_PATH, "ceres", "scripts")
      script = File.expand_path(File.join(script_path, filename))
      unless File.exists? script
        perror "Unable to find #{filename}: #{script}"
        return
      end

      scripts script
    end

    # maybe do this internally
    def create_dir_with_selection
      execute_script "create_dir_with_selection"
    end

    # allow user to select a script that generates filenames which
    #  will be displayed for selection or action.
    def generators
      write_selected_files

      title = "Select a generator"
      script_path = File.join(CONFIG_PATH, "ceres", "generators")
      binding = `find #{script_path} -type f | fzf --prompt="#{title} :"`.chomp
      return if binding.nil? || binding == ""

      # call generator and accept list of files
      @title = "Files from #{File.basename(binding)}"
      @files = `#{binding} "#{current_file}"`.split("\n", remove_empty: true)
    end

    # ------------- end of scripts --------------------------------#

    # ------------------- view_selected_files ------------------ #
    def view_selected_files
      fname = write_selected_files

      unless fname
        message "No file selected.    "
        return
      end

      system "$PAGER #{fname}"
      @screen.setup_terminal
    end

    # ------------- end of view_selected_files --------------------------------#

    def list_selected_files
      @title = "Selected Files"
      @files = selected_files

      bm = @bindings.key_for?("list_selected_files")
      @bm = " (" + bm + ")" if bm
    end

    # write selected files to a file and return path
    # if no selected files then blank out the file, or else
    # script could use old selection again.
    def write_selected_files
      # fname = File.join(File.dirname(CONFIG_FILE), 'selected_files')
      # 2019-04-10 - changed to ~/tmp otherwise confusion about location
      fname = File.join("~/tmp/", "selected_files")
      fname = File.expand_path(fname)

      # remove file if no selection
      if selected_files.empty?
        File.delete(fname) if File.exists?(fname)
        return nil
      end

      # FIXME: file starting with ~ loses first two characters.
      base = Pathname.new Dir.current
      File.open(fname, "w") do |file|
        selected_files.each do |row|
          # use relative filename. Otherwise things like zip and tar run into issues
          unless @selected_files_fullpath_flag
            p = Pathname.new(row)
            row = p.relative_path_from(base)
          end
          file.puts row
        end
      end

      return fname
    end

    ##
    # Editing of the User Dir List.
    # remove current entry from used dirs list, since we may not want some entries being there
    # Need to call this from somewhere. Test it out again.
    # Usage. Invoke `1` or `2` and select some files and then call remove
    def remove_from_list
      # XXX key to invoke this is difficult. make it easier
      selfiles = current_or_selected_files
      sz = selfiles.size
      print "Remove #{sz} files from used list (y)?: "
      key = get_char
      return if key != "y"

      arr = selfiles.map do |path|
        if path[0] != "/"
          File.expand_path(path)
        else
          path
        end
      end
      if File.directory? arr.first
        @used_dirs -= arr
        select_from_used_dirs
      else
        @visited_files -= arr
        select_from_visited_files
      end
      unselect_all
      @modified = true
      # redraw_required
    end


    # Get visited files and bookmarks that are inside this directory
    #  at a lower level.
    # 2019-03-23 - not exactly clear what is happening XXX
    # this gets a directory (containing '/' at end)
    def get_important_files(dir : String)
      # checks various lists like visited_files and bookmarks
      # to see if files from this dir or below are in it.
      # More to be used in a dir with few files.
      list = [] of String
      l = dir.size + 1

      # 2019-03-23 - i think we are getting the basename of the file
      #  if it is present in the given directory XXX
      @visited_files.each do |e|
        list << e[l..-1] if e.index(dir) == 0
      end

      # bookmarks if it starts with this directory then add it
      # FIXME it puts same directory cetus into the list with full path
      # We need to remove the base until this dir. get relative part
      list1 = @bookmarks.values.select do |e|
        e.index(dir) == 0 && e != dir
      end

      list.concat list1
      list
    end


    # set message which will be displayed in status line
    # TODO: maybe we should pad it 2019-04-08 -
    def message(mess)
      @message = mess
      @keys_to_clear = 2 if mess
    end




    def clear_message
      if @keys_to_clear != -1
        @keys_to_clear -= 1
        if @keys_to_clear == 0
          message nil
          @keys_to_clear = -1
        end
      end
    end

    # returns true if only cursor moved and redrawing not required
    def only_cursor_moved?
      # only movement has happened within this page, don't redraw
      return false unless @cursor_movement && @old_cursor != -1

      # if cursor has not moved (first or last item on screen)
      if @old_cursor == @cursor
        place_cursor # otherwise highlight vanishes if keep pressing UP on first row.
        @cursor_movement = false
        return true # next in the loop
      end

      # we may want to print debug info if flag is on
      if @toggles["debug_flag"]
        clear_last_line
        # print_debug_info
      else
        status_line
      end

      place_cursor
      @cursor_movement = false
      return true # next in the loop
    end

    # indicate that only cursor moved, so don't redraw or rescan
    def only_cursor_moved(flag = true)
      @cursor_movement = flag
    end

    # main loop which calls all other programs
    def run

      Signal::INT.trap do
        @screen.reset_terminal
        exit
      end

      at_exit{ @screen.reset_terminal }

      Signal::WINCH.trap do
        screen_settings
        redraw
        place_cursor
      end

      @screen.setup_terminal
      config_read
      @colorparser.parse_ls_colors # FIXME TODO
      set_bookmark "0"

      redraw true
      place_cursor

      # do we need this, have they changed after redraw XXX
      @patt = nil
      @sta = 0

      Loggy.debug "BEFORE LOOP"
      # forever loop that prints dir and takes a key
      loop do
        Loggy.debug "BEFORE getchar "
        key = KeyHandler.get_char
        Loggy.debug "AFTER getchar #{key}"

        unless resolve_key key # key did not map to file name, so don't redraw
          place_cursor
          next
        end

        break if @quitting

        next if only_cursor_moved?

        next unless @redraw_required # no change, or ignored key

        redraw rescan?
        place_cursor
        # 2019-04-26 - XXX removed, let it be default, let false be declared where reqd
        # redraw_required false
      end
      write_curdir
      puts "bye"
      config_write if @writing
      Loggy.close
      exit 0
    end
    # --- after breaking up
    def get_char
      KeyHandler.get_char
    end
    def clear_last_line(color=STATUS_COLOR)
      @screen.clear_last_line color
    end
    def last_line
      @screen.last_line
    end
    def selected_files
      @selection.selected_files
    end
  end # end class
end   # module

include Cet
include ColorConstants
c = Ceres.new
c.run
