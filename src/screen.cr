require "readline"
class Screen

  getter lines = 0
  getter columns = 0
  getter max_items = 0

  def initialize
    get_term_size
  end

  def get_term_size
    # Get terminal size ('stty' is POSIX and always available).
    # This can't be done reliably across all bash versions in pure bash.
    l, c = `stty size`.split(" ") #.map{ |e| e.to_i }
    @lines = l.to_i
    @columns = c.to_i

    # Max list items that fit in the scroll area.
    # This may change with caller, but needs to be recalculated whenever
    # screen size changes
    @max_items = @lines - 3
  end
  def clear_screen
    # Only clear the scrolling window (dir item list).
    # '\e[%sH':    Move cursor to bottom of scroll area.
    # '\e[9999C':  Move cursor to right edge of the terminal.
    # '\e[1J':     Clear screen to top left corner (from cursor up).
    # '\e[2J':     Clear screen fully (if using tmux) (fixes clear issues).
    # '\e[1;%sr':  Clearing the screen resets the scroll region(?). Re-set it.
    #              Also sets cursor to (0,0).
    ## if TMUX has a value then use clear
    ## if TMUX is blank, then return blank

    printf("\e[%sH\e[9999C\e[1J\e[1;%sr",
           @lines,
           @lines      )
  end
  def setup_terminal
    # Setup the terminal for the TUI.
    # '\e[?1049h': Use alternative screen buffer.
    # '\e[?7l':    Disable line wrapping.
    # '\e[?25l':   Hide the cursor.
    # '\e[2J':     Clear the screen.
    # '\e[1;Nr':   Limit scrolling to scrolling area.
    #              Also sets cursor to (0,0).
    # printf("\e[?1049h\e[?7l\e[?25l\e[2J\e[1;%sr", @max_items)
    printf("\e[?1049h\e[?7l\e[?25l\e[2J\e[1;%sr", @lines)
    # Hide echoing of user input
    system("stty -echo")
  end

  def reset_terminal
    # Reset the terminal to a useable state (undo all changes).
    # '\e[?7h':   Re-enable line wrapping.
    # '\e[?25h':  Unhide the cursor.
    # '\e[2J':    Clear the terminal.
    # '\e[;r':    Set the scroll region to its default value.
    #             Also sets cursor to (0,0).
    # '\e[?1049l: Restore main screen buffer.
    print("\e[?7h\e[?25h\e[2J\e[;r\e[?1049l")

    # Show user input.
    system("stty echo")
  end

  # Call before shelling to editor pager and when exiting
  def partial_reset_terminal
    # Reset the terminal to a useable state (undo all changes).
    # '\e[?7h':  Re-enable line wrapping.
    # '\e[?25h': Unhide the cursor.
    # '\e[2J':   Clear the terminal.
    # '\e[;r':   Set the scroll region to its default value.
    #            Also sets cursor to (0,0).
    # '\e[?1049l: Restore main screen buffer.
    print "\e[?7h\e[?25h\e[;r\e[?1049l"

    # Show user input.
    system "stty echo"
  end

  def post_cmd_line
    # '\e[%sH':  Move cursor back to cmd-line.
    # '\e[?25h': Unhide the cursor.
    printf("\e[%sH\e[?25h", @lines)

    # '\e[2K':   Clear the entire cmd_line on finish.
    # '\e[?25l': Hide the cursor.
    # '\e8':     Restore cursor position.
    printf "\e[2K\e[?25l\e8"
  end

  def move_to_bottom
    # '\e7':     Save cursor position.
    # '\e[?25h': Unhide the cursor.
    # '\e[%sH':  Move cursor to bottom (cmd_line).
    # printf("\e7\e[%sH\e[?25h", @lines)
    printf("\e[%sH", @lines)
  end
    def last_line
      # system "tput cup #{@lines} 0"
      print "\e[#{@lines};0H"
      # tput_cup @lines, 0
    end
    def clear_last_line(status_color)
      last_line
      # print a colored line at bottom of screen
      # \e[33;41m  - set color of status_line
      # %*s        - set blank spaces for entire line
      # \e[m       - reset text mode
      # \r         - bring to start of line since callers will print.
      # print format("\e[33;4%sm%*s\e[m\r", @status_color || "1", @columns, " ")
      print "\e[33;4%sm%*s\e[m\r" % [ status_color || "1", @columns, " " ]
    end
    # print right aligned
    # XXX does not clear are, if earlier text was longer then that remains.
    # TODO: 2019-04-10 - this should update a variable, and status_line
    # should clear and reprint mode, message, patt and right text
    def print_on_right(text, color)
      sz = text.size
      col = @columns - sz - 1
      col = 2 if col < 2
      text = text[0..@columns - 3] if sz > @columns - 2
      # 2019-04-22 - earlier direct system call to tput, now trying print
      # system "tput cup #{@lines} #{col}"
      tput_cup @lines, @columns - sz - 1
      # print text
      print "\e[33;4#{color}m#{text}\e[m"
    end

  def status_line(color, text)
    # '\e7':       Save cursor position.
    #              This is more widely supported than '\e[s'.
    # '\e[%sH':    Move cursor to bottom of the terminal.
    # '\e[30;41m': Set foreground and background colors.
    # '%*s':       Insert enough spaces to fill the screen width.
    #              This sets the background color to the whole line
    #              and fixes issues in 'screen' where '\e[K' doesn't work.
    # '\r':        Move cursor back to column 0 (was at EOL due to above).
    # '\e[m':      Reset text formatting.
    # '\e[H\e[K':  Clear line below status_line.
    # '\e8':       Restore cursor position.
    #              This is more widely supported than '\e[u'.
    printf "\e7\e[%sH\e[30;4%sm%*s\r%s\e[m\e[%sH\e[K\e8", \
      @lines-1, \
      color, \
      @columns, " ", \
      text, \
      @lines
  end
  def reset_cursor_position
    printf "\e[H"
  end
  def unhide_cursor
    printf "\e[?25h"
  end
  def hide_cursor
    printf "\e[?25l"
  end
  def save_cursor_position
    printf "\e7"
  end
  def restore_cursor_position
    printf "\e8"
  end
  def clear_line
    print "\e[K"
  end
  def move_cursor_up
    print "\e[A"
  end
  def insert_line_above
    print "\e[L"
  end

  # Confirm action, return true or false.
  # True returned if Y or y pressed.
  def confirm(prompt)
    # '\e7':     Save cursor position.
    # '\e[?25h': Unhide the cursor.
    # '\e[%sH':  Move cursor to bottom (cmd_line).
    # printf("\e7\e[%sH\e[?25h", @lines)
    save_cursor_position
    move_to_bottom
    unhide_cursor

    print prompt
    yn = KeyHandler.get_char
    post_cmd_line # check if this is required
    yn =~ /[Yy]/
  end

  # The original cmd_line takes variable arguments and has different processing
  # for different cases. I have simplified it here.
  # inc-search should be separate. getting a yes/no should be separate.
  def cmd_line(prompt)

    # '\e7':     Save cursor position.
    # '\e[?25h': Unhide the cursor.
    # '\e[%sH':  Move cursor to bottom (cmd_line).
    # printf("\e7\e[%sH\e[?25h", @lines)
    save_cursor_position
    move_to_bottom
    unhide_cursor

    reply = Readline.readline(prompt, true)
    reply
  end
    # place cursor on row and col taking first two rows into account
    def tput_cup(row, col)
      # we add 3: 2 is for the help and directory line. 1 is since tput is 1 based
      print "\e[#{row + 3};#{col + 1}H"
    end
end
