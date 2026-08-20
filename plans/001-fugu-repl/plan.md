# 001 — Fugu::REPL, a line editor for an operator prompt

## Status

Proposed.

## Purpose

`Fugu::REPL` reads one operator command line from a terminal. It edits the line,
completes a word, keeps a session history, and filters untrusted bytes before it
shows them. It operates inside the `stdio tty` promises of pledge(2).

## Why Fugu holds this module

Two FuguBSD tools need the same operator prompt, and both specify it today:

| Repo | Unit | Rules | Need |
| --- | --- | --- | --- |
| FuguPass | `CLI-IFACE` | CLI-IFACE-4, CLI-IFACE-5, CLI-IFACE-6, CLI-IFACE-7 | Terminal ownership, the display filter, a watched reply pipe, and a plain non-terminal mode |
| FuguPass | `CLI-SPLIT` | CLI-SPLIT-7 | `fugupass-repl` is Perl on the Fugu library, under `stdio tty` |
| FuguPass | `CLI-REPL` | CLI-REPL-3, CLI-REPL-8 | A command table, tab completion, and a memory-only history |
| FuguTTX | `HRN-REPL` | HRN-REPL-1 to HRN-REPL-9 | The same editor, the same filter, the same watched handle |

The FuguPass register and the FuguTTX register each carry the same note: the
module does not exist yet, and its interface contract lands in this repository
with the implementation. This plan is that contract.

A line editor is a terminal utility. It reads a descriptor, it drives termios,
and it holds no policy of any consumer. It therefore belongs in `Fugu::`,
beside `Fugu::CLI`, which parses a command line that a shell already read.

## Scope

In scope:

- One line of input, with an emacs-style key subset.
- Word completion through a callback.
- A session history in memory.
- A display filter for untrusted bytes.
- A yes-or-no confirmation prompt with the default no.
- Extra read handles that end the prompt read.
- A plain mode for input that is not a terminal.
- A command table that generates the help text.

Out of scope:

- A history file. A history file leaks the words that an operator typed.
- A terminfo lookup. A terminfo read needs the `rpath` promise, and the module
  must operate under `stdio tty`.
- A full readline replacement: no vi mode, no macros, no key rebinding, and no
  incremental history search.
- A command dispatcher. The caller dispatches. `Fugu::CLI` covers the
  command-line form of the same tool.
- Colour and cursor addressing beyond the fixed control sequences that the key
  subset needs.

## Constraints that shape the design

- **The module must stand alone.** FuguTTX HRN-REPL-2 states that the module
  must not load an other Fugu module. The module therefore uses core Perl only:
  `POSIX`, `IO::Select`, and `Encode`. It must not use `Fugu::Log`, and it must
  not log. Every failure is a return value.
- **The module must operate under `stdio tty`.** It must not open a file, must
  not create a process, and must not reach the network. termios and the window
  size come from ioctl(2) calls that the `tty` promise covers.
- **The module must read with sysread(2).** A buffered read can take more bytes
  than the caller consumes. Then select(2) reports no more input, and the rest
  of the line never arrives. The module keeps its own input buffer.
- **The module must restore the terminal on every exit path.** It holds raw mode
  only while it reads. `restore` is idempotent, and the destructor calls it.

## The interface contract

### new

`new(%args)` builds an editor. The method opens nothing and changes no terminal
setting.

| Argument | Meaning |
| --- | --- |
| `in` | The input handle. The default is `STDIN`. |
| `out` | The output handle. The default is `STDOUT`. |
| `prompt` | The prompt string. The default is `> `. |
| `commands` | The command table, as a hash reference of name to summary. |
| `prefix` | The command prefix, as a string. The default is the empty string. |
| `complete` | A code reference for word completion. |
| `watch` | Extra read handles, as an array reference. |
| `history_size` | The count of lines that the history keeps. The default is 500. |

`commands` and `prefix` describe one command language. FuguPass uses bare
command words, so its prefix is empty. FuguTTX marks a client command with a
solidus, so its prefix is `/`.

`new` dies when `complete` is not a code reference, and when `watch` holds a
handle with no descriptor. Both are programming errors.

### read_line

`read_line()` reads one line and returns it, without the terminator.

The method returns `undef` at an end of file, when a watched handle becomes
readable, and when the operator interrupts the line. `event()` reports which of
the four outcomes occurred, so a caller never guesses.

The method holds raw mode only for the length of the call.

### event

`event()` returns the outcome of the most recent `read_line` or `confirm` call:
`line`, `eof`, `watch`, or `interrupt`.

An interrupt at the prompt clears the line. It does not end the session.
FuguTTX HRN-REPL-5 needs that difference, because an interrupt during a step
sends a cancel instead.

### ready_handle

`ready_handle()` returns the watched handle that ended the read, after an event
of `watch`. It returns `undef` otherwise.

A closed handle is readable at an end of file. Thus a caller learns that its
peer went away, and the caller decides what that means. FuguPass CLI-IFACE-6 and
FuguTTX HRN-REPL-8 both need this.

### confirm

`confirm($question)` asks a yes-or-no question. The method returns 1 for yes and
0 for every other answer. The default is no. An end of file and an interrupt
both answer no.

A gate that a stray keystroke can open is not a gate. FuguTTX HRN-REPL-6 states
the same rule.

### display_filter

`display_filter($bytes)` returns the bytes that are safe to show. This is a
plain function, not a method, because a caller filters bytes that no editor
read.

The filter keeps printable ASCII, the line feed, and the horizontal tab. It
removes `DEL` (0x7F) and the C1 range (0x80 to 0x9F). It replaces every other
byte with one question mark. It must not break a UTF-8 sequence: a valid
sequence survives whole, and an invalid byte becomes one question mark.

An escape sequence in tool output can rewrite what the operator sees, and it can
hide the change that the operator is about to approve. FuguPass CLI-IFACE-5 and
FuguTTX HRN-SAFE-DISPLAY state the same rule, so the filter lives in one place.

### show

`show($bytes)` filters the bytes with `display_filter` and writes them to the
output handle. The method returns the object.

### help_text

`help_text()` returns the help for the command table: one line for each command,
with the prefix, the name, and the summary, in sorted order.

The module generates the help, so the table and the help cannot disagree.

### history

`history()` returns the session history, oldest first.
`add_history($line)` appends one line and drops the oldest line above
`history_size`.

`read_line` appends a line that is not empty and that is not the previous line.
The history lives in memory only, for the session. The module must not write a
history file.

### is_interactive

`is_interactive()` returns 1 when the input handle is a terminal. It returns 0
otherwise.

With a 0 answer the module reads plain lines: no editing, no history recall, and
no escape output. Scripted tests drive a session in this mode. FuguPass
CLI-IFACE-7 and FuguTTX HRN-REPL-9 both need it.

### prompt, commands, watch

`prompt($string)` sets or reads the prompt.
`commands($hashref)` sets or reads the command table.
`watch($arrayref)` sets or reads the watched handles.

A caller changes the completion set when the session state changes. FuguPass
CLI-REPL-8 completes entry names from the open index, and the index opens after
the unlock.

### restore

`restore()` puts the terminal settings back. The method is idempotent and
returns the object. The destructor calls it.

## The key subset

The editor implements one fixed set of keys. The sequences are the ANSI
sequences, hard-coded, because a terminfo read needs `rpath`.

| Key | Action |
| --- | --- |
| `Enter` | Accept the line |
| `Tab` | Complete the word before the cursor |
| `Ctrl-A`, `Home` | Go to the start of the line |
| `Ctrl-E`, `End` | Go to the end of the line |
| `Ctrl-B`, `Left` | Go back one character |
| `Ctrl-F`, `Right` | Go forward one character |
| `Ctrl-P`, `Up` | Recall the previous history line |
| `Ctrl-N`, `Down` | Recall the next history line |
| `Backspace`, `Ctrl-H` | Delete the character before the cursor |
| `Ctrl-D` | Delete the character under the cursor, or end the input on an empty line |
| `Ctrl-K` | Delete to the end of the line |
| `Ctrl-U` | Delete the whole line |
| `Ctrl-W` | Delete the word before the cursor |
| `Ctrl-L` | Draw the line again |
| `Ctrl-C` | Clear the line and report an interrupt |

An unknown escape sequence does nothing. The editor must not insert its bytes
into the line.

## Completion

The `complete` callback receives the word before the cursor and the whole line.
It returns the candidate list.

The module completes a command name from the command table when the cursor is in
the first word. It calls the callback otherwise. One candidate replaces the
word. Several candidates extend the word to the common prefix, and a second
`Tab` shows the list.

The callback runs in the caller's process, at the prompt. A callback that blocks
blocks the prompt.

## Load contract

The module needs core Perl only. It adds no line to the `cpanfile` and no line
to a `deps/` manifest. `t/fugu/coreperl.t` proves the load contract, and
`t/protocol/boundary.t` proves that no `App::` namespace enters.

The module must not load an other `Fugu::` module. A test asserts this, because
FuguTTX HRN-REPL-2 depends on it, and a later change could break it silently.

## Files

| File | Content |
| --- | --- |
| `lib/Fugu/REPL.pm` | The module |
| `lib/Fugu/REPL.pod` | The API sidecar |
| `lib/Fugu.pod` | One index entry for the module |
| `t/fugu/repl.t` | The unit test |
| `README.md` | One row in the module table, if the table lists modules |

## Tests

`t/fugu/repl.t` uses `Test::More` and `done_testing()`. It drives the module
over a pipe pair, so it needs no terminal.

The test proves:

- The plain mode reads whole lines, and it reads a line that arrives in pieces.
- The plain mode reports `eof` at an end of file.
- A watched handle that becomes readable ends the read with the event `watch`,
  and `ready_handle` names it.
- A watched handle that closes ends the read with the event `watch`.
- `display_filter` keeps printable ASCII, the line feed, and the tab.
- `display_filter` removes `DEL` and every C1 byte.
- `display_filter` keeps a valid UTF-8 sequence whole.
- `display_filter` replaces an invalid byte with one question mark.
- `confirm` answers no for an empty answer, for `n`, and at an end of file.
- `confirm` answers yes for `y` and for `yes`, in each letter case.
- `help_text` lists every command, sorted, with the prefix.
- The history holds no empty line and no immediate repeat.
- The history drops the oldest line above `history_size`.
- The module loads no other `Fugu::` module.
- `restore` is safe to call two times.
- The editor mode skips gracefully when the test has no terminal.

## Acceptance

- `make check` passes: `make lint`, `make test`, `make tidy`, and
  `make spec-coverage`.
- `t/scripts/symbols.t` passes: every public sub has a caller in `lib/` or in a
  test.
- `t/fugu/coreperl.t` passes: the module loads with core Perl only.
- The `.pod` sidecar documents every public sub, with the sections that the other
  sidecars use.

## Open questions

1. **The second `Tab` display.** A candidate list can be longer than the
   terminal. The plan shows the list and draws the prompt again. A page mode
   needs a decision, and no consumer asks for one today.
2. **Wide characters.** The editor counts bytes of a UTF-8 sequence as one
   character for the cursor. A double-width character then draws one column
   short. No consumer needs a full width table today, so the plan leaves it out.
