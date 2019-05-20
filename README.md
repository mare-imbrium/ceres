# cet

crystal port of cetus file manager/navigator (ruby)

This is my first crystal program, for learning.

`cetus` is a file-manager and action launcher written in ruby. I've been using it for many years, and it is itself based on `lyra` (and `zfm`) which used a different indexing mechanism.

In case you check this out, do give me suggestions about better coding practices.

## Usage

- Pressing "?" provides help on keys.
- Tilde is the menu key which provides various actions.
- `=` is a toggle key allowing changing of various flags and options.
- `C-x` is a menu for file actions.

This program differs from other command-line file managers in that each file has
a shortcut or hotkey for opening it. Hotkeys are from a to y, za to zz ..

This reduces the need for arrow keys allowing us to jump to a file or directory
with one or two keys, but also means that `j` and `k` cannot be used
for navigation.

Another difference is that filenames are displayed in multiple columns. Other listers show only one column so a lot of paging is required.

By default most files are opened using a pager. One may open using an editor using `Ctrl-e` or using the `open` command using `Ctrl-o`. One may switch to `editor mode` so that files are opened using `$EDITOR`.

== Scripts and Generators

Some programs generate lists of files or directories. `z` is one such utility. Tilde-z reads up files from the `z` database for selection. One may have other such scripts or utilities for generating lists and can place them in the `generators` directory.

Actions on selected files are contained in the `scripts` directory. Some actions are removing spaces from filenames, extracting audio from video files, converting to mp3 and so one. One may place other scripts in the `scripts` folder.

== Visited files and directories

This program keeps a list of files that have been opened, and directories in which some action has happened. One can quickly get a list of such files or dirs and jump to them using the tilde menu or a hotkey.

== Configuration

THis program maintains three lists. The first is a hash of bookmarks (character and directory). Bookmarks allow quick access to frequently used directories.

The two others are the lists of used files and directories.

## Development

The original `cetus` program used reflection (`send`) to call methods. Keys and their bindings were maintained in a hash, and the appropriate method was called by reading the hash.

Crystal does not support `send` so calls to programs are hard-coded. It is possible that some key has not yet been mapped in the dispatch method. Please notify me if that is the case.

There is very little difference in the performance of the ruby and crystal program. This is because the ruby program was already very fast in displaying a list of files. The crystal version is slightly faster.

I've also refactored the program (the ruby version is one file with no classes_). There could be some errors after refactoring. I may continue to break this into more classes as time goes by.


## Contributing

1. Fork it (<https://github.com/mare-imbrium/cet/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [kepler](https://github.com/mare-imbrium) - creator and maintainer
