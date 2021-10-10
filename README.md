# begrudge: convert ANSI-escaped colorized terminal output to classed HTML

`begrudge` is a small tool written in Zig to convert colorized terminal output
that uses [ANSI escape
sequences](https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797) into
class-based HTML snippets. It may be useful for converting the output of tools
such as [`bat`](https://github.com/sharkdp/bat) or
[`glow`](https://github.com/charmbracelet/glow) into something web browsers can
understand, without the need to reinvent or even modify those renderers.

`begrudge` does not attempt to implement all known ANSI escape sequence
commands or the entire [Paul Flo Williams state
machine](https://vt100.net/emu/dec_ansi_parser), instead implementing the same
subset as [a2h(1)](https://rtomayko.github.io/bcat/a2h.1.html), a similar tool
written in Ruby (though a2h's code was not used here), thus, the following
escape sequences are supported:

```
<ESC>[0m
    Resets all attributes / closes all HTML tags.
<ESC>[1m=<span class='begrudge-bold'>
    Bold.
<ESC>[4m=<span class='begrudge-underscore'>
    Underscore.
<ESC>[5m=<span class='begrudge-blink'>
    Blink. For goodness' sake, please don't actually make your CSS blink this.
<ESC>[8m=<span class='begrudge-span'>
    Hidden.
<ESC>[30-37m=<span class='begrudge-fg-0'>
    Foreground color (30 -> 0, 37 -> 7, you get the idea).
    Escape 38, "default color", is not yet implemented.
<ESC>[40-47m=<span style='background-color:color>
    Background color (40 -> 0, 47 -> 7, you get the idea).
    Escape 48, "default color", is not yet implemented.
<ESC>[90-97m=<span style='color:color>
    Bright foreground color (90 -> 0, 97 -> 7, you get the idea).
<ESC>[100-107m=<span style='background-color:color>
    Bright background color (100 -> 0, 107 -> 7, you get the idea).
```

I personally consider truecolor (full rgb) terrible UX (if I set a 16 colour
palette, use it, damn it, I don't care about your design choices) and thus will
stubbornly be refusing to implement support for it for now. if you hate this
decision, you have three options:

- write it in a fork and go on to achieve world domination with said fork,
  to which I could well remain blissfully ignorant forever
- write it and submit a patch. I'll merge it if it's clean, tested code,
  even if it will, I insist, bring disorder and chaos to the cosmos
- bug me about it until I cave and write a truecolor to `<span style=...>`
  translator

## Getting Started

To my knowledge, `begrudge` is not yet packaged anywhere. You'll need to build
it from source using a Zig 0.8 compiler (newer Zigs, namely the 0.9 nightlies,
may work, but as of yet are untested). The standard `zig build` workflow is
supported. There are no dependencies outside of the standard library. On Linux,
at least, the produced binary has no sofile (dynamic linking) dependencies at
runtime, either.

`begrudge` has no command line arguments: simply pipe ANSI-escaped data into
it, and it will spit out the HTML span-ified version to standard output. For
example, to render `begrudge`'s own source via `bat(1)`, which uses
[syntect's](https://github.com/trishume/syntect) engine under the hood:

```sh
bat -fp --theme=ansi begrudge.zig | zig build -Drelease-fast run

# ...
# <span class='begrudge-fg-5'>const</span> std <span class='begrudge-fg-5'>=</span> <span class='begrudge-fg-5'>@import</span>(<span class='begrudge-fg-2'>"std"</span>);
# <span class='begrudge-fg-5'>const</span> eql <span class='begrudge-fg-5'>=</span> std.mem.eql;
# <span class='begrudge-fg-5'>const</span> expect <span class='begrudge-fg-5'>=</span> std.testing.expect;
# <span class='begrudge-fg-5'>const</span> expectEqual <span class='begrudge-fg-5'>=</span> std.testing.expectEqual;
# <span class='begrudge-fg-5'>const</span> expectEqualStrings <span class='begrudge-fg-5'>=</span> std.testing.expectEqualStrings;
# <span class='begrudge-fg-5'>const</span> trimLeft <span class='begrudge-fg-5'>=</span> std.mem.trimLeft;
```

To integrate with `glow(1)`, try `PAGER="zig build -Drelease-fast run" glow -p
README.md` (however, note that `glow(1)`'s output is not especially polite - it
has a tendency to set styles, print a single character, reset the terminal, and
repeat, over and over and over. I plan to work around this with a smarter
diffing engine in `begrudge` at some point).

You could extend this further, perhaps wrapping the entire thing in `<pre>`,
writing a stylesheet mapping the couple dozen possible classes to CSS styles,
and putting it on your blog as a snippet system. You may also be interested in
my other project (that spawned the idea for `begrudge` in the first place),
[`gawsh`](https://github.com/klardotsh/gawsh) (still under extremely early
development at time of writing).

## Copying, Contributing, and Legal

`begrudge`'s implementation, specification, documentation, artwork, and other
assets are all [Copyfree](http://copyfree.org/), released under the [Creative
Commons Zero 1.0
dedication](https://creativecommons.org/publicdomain/zero/1.0/). This means
you're free to use it for any purpose, in any context, and without letting me
know.

Contributions will be considered, but are not guaranteed to be merged for any
reason or no reason at all. By submitting a contribution to `begrudge`, you assert
the following (this is the [Unlicense waiver](https://unlicense.org/WAIVER)):

> I dedicate any and all copyright interest in this software to the
> public domain. I make this dedication for the benefit of the public at
> large and to the detriment of my heirs and successors. I intend this
> dedication to be an overt act of relinquishment in perpetuity of all
> present and future rights to this software under copyright law.
>
> To the best of my knowledge and belief, my contributions are either
> originally authored by me or are derived from prior works which I have
> verified are also in the public domain and are not subject to claims
> of copyright by other parties.
>
> To the best of my knowledge and belief, no individual, business,
> organization, government, or other entity has any copyright interest
> in my contributions, and I affirm that I will not make contributions
> that are otherwise encumbered.
