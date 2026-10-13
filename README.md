# fsearch.yazi

A [Yazi](https://github.com/sxyazi/yazi) plugin that searches file and folder names with
[fsearch](https://github.com/noahdunnagan/fsearch) instead of `fd`.

fsearch answers from its index of the full disk in milliseconds, so the list changes
while you type. `fd` reads every folder first, which takes seconds in a large folder.

The plugin is for macOS only, because fsearch is for macOS only.

## Requirements

- Yazi 26.9.1. See [Yazi version](#yazi-version).
- [fsearch](https://github.com/noahdunnagan/fsearch) on the `PATH`. The plugin was tested
  with fsearch v0.2.1. Start fsearch from a terminal app that has Full Disk Access.
- `fd`, which Yazi's own search uses. The plugin uses it where fsearch has no index.

## Install

```sh
ya pkg add stefankuksenko/fsearch
```

Then give the plugin a key in `~/.config/yazi/keymap.toml`. This example replaces `s`,
the key of Yazi's own search with `fd`:

```toml
[mgr]
prepend_keymap = [
  { on = "s", run = "plugin fsearch", desc = "Search names with fsearch" },
]
```

## Use

Press the key and type. The plugin searches the names below the current folder.

- The list changes while you type. A pause of 0.1 second starts a search.
- The list that changes has 1,000 names at most. Return keeps the list. If that list
  was not complete, Return gets the full list.
- Escape two times, or Control+C, closes the prompt and returns to the view from
  before the search.
- The result is Yazi's usual search view. You can filter it, copy from it, and return
  to the folder with Escape.
- The prompt is at the bottom of the screen, so it does not hide the first names of
  the list.

One word is a regex on the name, as with `fd`. Letter case never matters.

With several words (5 at most), each word must be in the path below the folder, in any
order, and one of the words must be in the name:

- `invoice 2025` finds `2025/invoice-march.pdf`, `invoices/2025-march.pdf` and the folder
  `invoice-2025`.
- It does not find `invoice-2025/scan.pdf`, because that name has none of the words.

Each word is still a regex: `invoice pdf$` gives only PDF files. There is no tolerance
for a wrong letter. For a name with a space, type `.` or `\s` in place of the space. A
regex that is not complete gives no notice until Return.

## When fd does the search

Yazi's own `fd` search opens (the prompt says "Search via fd") when fsearch cannot give
all names below the folder:

- fsearch is not installed;
- the fsearch daemon runs without Full Disk Access, and then it skips Desktop,
  Documents, Downloads and the cloud folders;
- the folder is on another volume (a USB disk, a disk image), which fsearch does not
  index;
- the folder is a link, for which fsearch gives the real paths;
- the folder is empty.

For a volume that is mounted below the folder, the plugin adds the matches that `fd`
finds on that volume. The list that changes while you type does not include them.

## Differences from Yazi's fd search

- Several words are one search (see above). `fd` takes the full text as one regex.
- Letter case never matters. `fd` matches the case when the text has a capital letter.
- Git-ignored files are in the list, for example those in `node_modules`. `fd` skips
  them.
- From `/`, each file is in the list one time. `fd` also lists it again below
  `/System/Volumes/Data`.
- Hidden files are in the list only when Yazi shows hidden files, as with `fd`.
- fsearch returns 100,000 names at most. At that number, a notice says that the list
  is not complete.
- A name can store `й` and `ё` as two characters: the letter and its mark. The plugin
  matches both forms of these two letters.

## Yazi version

The plugin fills the search view with `Url:into_search`, `fs.op` and the `update_files`
action. The Yazi documentation does not list these calls. The official `vcs-files`
plugin uses the same calls on Yazi 26.9.1. A later Yazi version can change them, and
then the plugin needs the same change.

## License

MIT
